function [ins_gps_e] = ins_gps(imu, gps, att_mode, precision)
% ins: loosely-coupled integrated navigation system. It integrates IMU and GPS
% measurements using an Extended Kalman filter.
%
% INPUT:
%   imu, IMU data structure.
%         t: Ix1 time vector (seconds).
%        fb: Ix3 accelerations vector in body frame XYZ (m/s^2).
%        wb: Ix3 turn rates vector in body frame XYZ (radians/s).
%       arw: 1x3 angle random walks (rad/s/root-Hz).
%       vrw: 1x3 angle velocity walks (m/s^2/root-Hz).
%      gstd: 1x3 gyros standard deviations (radians/s).
%      astd: 1x3 accrs standard deviations (m/s^2).
%    gb_fix: 1x3 gyros static biases or turn-on biases (radians/s).
%    ab_fix: 1x3 accrs static biases or turn-on biases (m/s^2).
%  gb_drift: 1x3 gyros dynamic biases or bias instabilities (radians/s).
%  ab_drift: 1x3 accrs dynamic biases or bias instabilities (m/s^2).
%   gb_corr: 1x3 gyros correlation times (seconds).
%   ab_corr: 1x3 accrs correlation times (seconds).
%     gpsd : 1x3 gyros dynamic biases PSD (rad/s/root-Hz).
%     apsd : 1x3 accrs dynamic biases PSD (m/s^2/root-Hz);
%      freq: 1x1 sampling frequency (Hz).
% ini_align: 1x3 initial attitude at t(1).
% ini_align_err: 1x3 initial attitude errors at t(1).
%
%	gps, GPS data structure.
%         t: Mx1 time vector (seconds).
%       lat: Mx1 latitude (radians).
%       lon: Mx1 longitude (radians).
%         h: Mx1 altitude (m).
%       vel: Mx3 NED velocities (m/s).
%       std: 1x3 position standard deviations (rad, rad, m).
%      stdm: 1x3 position standard deviations (m, m, m).
%      stdv: 1x3 velocity standard deviations (m/s).
%      larm: 3x1 lever arm (x-right, y-fwd, z-down) (m).
%      freq: 1x1 sampling frequency (Hz).
%
%	att_mode, attitude mode.
%      'quaternion': attitude updated in quaternion format. Default value.
%             'dcm': attitude updated in Direct Cosine Matrix format.
%
%   precision, finite number precision.
%      double: double float precision (64 bits). Default value.
%      single: single float precision (32 bits).
%
% OUTPUT:
%   ins_gps_e, INS/GPS estimates data structure.
%         t: Ix1 time vector (seconds).
%      roll: Ix1 roll (radians).
%     pitch: Ix1 pitch (radians).
%       yaw: Ix1 yaw (radians).
%       vel: Ix3 NED velocities (m/s).
%       lat: Ix1 latitude (radians).
%       lon: Ix1 longitude (radians).
%         h: Ix1 altitude (m).
%    P_diag: Mx21 P matrix diagonals.
% Bias_comp: Mx12 Kalman filter biases compensations.
%    Y_inno: Mx6  Kalman filter innovations.
%         X: Mx21 Kalman filter states evolution.
%
%   Copyright (C) 2014, Rodrigo Gonzalez, all rights reserved.
%
%   This file is part of NaveGo, an open-source MATLAB toolbox for
%   simulation of integrated navigation systems.
%
%   NaveGo is free software: you can redistribute it and/or modify
%   it under the terms of the GNU Lesser General Public License (LGPL)
%   version 3 as published by the Free Software Foundation.
%
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%   GNU Lesser General Public License for more details.
%
%   You should have received a copy of the GNU Lesser General Public
%   License along with this program. If not, see
%   <http://www.gnu.org/licenses/>.
%
% Reference:
%   R. Gonzalez, J. Giribet, and H. Patiño. NaveGo: a
% simulation framework for low-cost integrated navigation systems,
% Journal of Control Engineering and Applied Informatics, vol. 17,
% issue 2, pp. 110-120, 2015. Alg. 2.
%
% Version: 001
% Date:    2016/11/15
% Author:  Rodrigo Gonzalez <rodralez@frm.utn.edu.ar>
% URL:     https://github.com/rodralez/navego

if nargin < 4, att_mode = 'quaternion'; end
if nargin < 5, precision = 'double'; end

ti = imu.t;
tg = gps.t;

Mi = (max(size(ti)));
Mg = (max(size(tg)));

if strcmp(precision, 'single')  % single precision
    
    % Preallocate memory for estimates
    roll_e  =  single(zeros (Mi, 1));
    pitch_e =  single(zeros (Mi, 1));
    yaw_e   =  single(zeros (Mi, 1));
    vel_e   =  single(zeros (Mi, 3));
    h_e     =  single(zeros (Mi, 1));
    x = single(zeros(21,1));
    
    % Constant matrices
    I =  single(eye(3));
    Z =  single(zeros(3));
    
    % Kalman matrices for later analysis
    Inn = single(zeros(Mg, 6));     % Kalman filter innovations
    P_d = single(zeros(Mg, 21));    % Diagonal from matrix P
    X =  single(zeros(Mg, 21));     % Evolution of Kalman filter states
    B =  single(zeros(Mg, 12));     % Biases compensantions after Kalman filter correction
    
    % Initialize biases variables
    gb_drift = single(imu.gb_drift');
    ab_drift = single(imu.ab_drift');
    gb_fix = single(imu.gb_fix');
    ab_fix = single(imu.ab_fix');
    vel_e(1,:) = single(zeros(1,3));
    
    % Initialize estimates at tti=1
    roll_e (1) = single(imu.ini_align(1));
    pitch_e(1) = single(imu.ini_align(2));
    yaw_e(1)   = single(imu.ini_align(3));
    vel_e(1,:) = single(gps.vel(1,:));
    h_e(1)     = single(gps.h(1));
    
else % double precision
    
    % Preallocate memory for estimates
    roll_e  =  (zeros (Mi, 1));
    pitch_e =  (zeros (Mi, 1));
    yaw_e   =  (zeros (Mi, 1));
    vel_e   =  (zeros (Mi, 3));
    h_e     =  (zeros (Mi, 1));
    x = (zeros(21,1));
    
    % Constant matrices
    I =  (eye(3));
    Z =  (zeros(3));
    
    % Kalman matrices for later analysis
    Inn = (zeros(Mg, 6));           % Kalman filter innovations
    P_d = (zeros(Mg, 21));          % Diagonal from matrix P
    X =  (zeros(Mg, 21));           % Evolution of Kalman filter states
    B =  (zeros(Mg, 12));           % Biases compensantions after Kalman filter correction
    
    % Initialize biases variables
    gb_drift = imu.gb_drift';
    ab_drift = imu.ab_drift';
    gb_fix = imu.gb_fix';
    ab_fix = imu.ab_fix';
    
    % Initialize estimates at tti = 1
    roll_e (1) = imu.ini_align(1);
    pitch_e(1) = imu.ini_align(2);
    yaw_e(1)   = imu.ini_align(3);
    vel_e(1,:) = gps.vel(1,:);
    h_e(1)     = gps.h(1);
end

% Lat and lon cannot be set in single precision. They need full (double) precision.
lat_e    = zeros (Mi,1);
lon_e    = zeros (Mi,1);
lat_e(1) = double(gps.lat(1));
lon_e(1) = double(gps.lon(1));

DCMnb = euler2dcm([roll_e(1); pitch_e(1); yaw_e(1);]);
DCMbn = DCMnb';
qua = euler2qua([roll_e(1) pitch_e(1) yaw_e(1)]);

% Kalman filter matrices
S.R = diag([gps.stdv, gps.stdm].^2);
S.Q = (diag([imu.arw, imu.vrw, imu.gpsd, imu.apsd].^2));
S.P = diag([imu.ini_align_err, gps.stdv, gps.std, imu.gstd, imu.astd, imu.gb_drift, imu.ab_drift].^2);

% UD filter matrices
% [Up, Dp] = myUD(P);
% dp = diag(Dp);

% Initialize matrices for INS performance analysis
P_d(1,:) = diag(S.P)';
B(1,:)  = [gb_fix', ab_fix', gb_drift', ab_drift'];

% INS index
i = 2;

% GPS clock is the master clock
for j = 2:Mg
    
    
    while (ti(i) < tg(j))
        
        %% INERTIAL NAVIGATION SYSTEM (INS)
        
        % Print a dot on console every 10,000 INS executions
        if (mod(i,10000) == 0), fprintf('. '); end
        % Print a return on console every 200,000 INS executions
        if (mod(i,200000) == 0), fprintf('\n'); end
        
        % INS period
        dti = ti(i) - ti(i-1);
        
        % Correct inertial sensors
        wb_corrected = (imu.wb(i,:)' - gb_drift - gb_fix);
        fb_corrected = (imu.fb(i,:)' - ab_drift - ab_fix);
        
        % Attitude update
        omega_ie_N = earthrate(lat_e(i-1), precision);
        omega_en_N = transportrate(lat_e(i-1), vel_e(i-1,1), vel_e(i-1,2), h_e(i-1));
        
        [qua_n, DCMbn_n, ang_v] = att_update(wb_corrected, DCMbn, qua, ...
            omega_ie_N, omega_en_N, dti, att_mode);
        roll_e(i) = ang_v(1);
        pitch_e(i)= ang_v(2);
        yaw_e(i)  = ang_v(3);
        DCMbn = DCMbn_n;
        qua = qua_n;
        
        % Gravity update
        g = gravity(lat_e(i-1), h_e(i-1));
        
        % Velocity update
        fn = DCMbn_n * (fb_corrected);
        vel_upd = vel_update(fn, vel_e(i-1,:)', omega_ie_N, omega_en_N, g', dti); %
        vel_e (i,:) = vel_upd';
        
        % Position update
        pos = pos_update([lat_e(i-1) lon_e(i-1) double(h_e(i-1))], double(vel_e(i,:)), double(dti) );
        lat_e(i) = pos(1); lon_e(i) = pos(2); h_e(i) = (pos(3));
        
        % Magnetic heading update
        %  yawm_e(i) = hd_update (imu.mb(i,:), roll_e(i),  pitch_e(i), D);
        
        % Index for INS navigation update
        i = i + 1;
        
    end
    
    %% INNOVATIONS
    
    [RM,RN] = radius(lat_e(i-1), precision);
    Tpr = diag([(RM+h_e(i-1)), (RN+h_e(i-1))*cos(lat_e(i-1)), -1]);  % radians-to-meters
    
    % Innovations
    zp = Tpr * ([lat_e(i-1); lon_e(i-1); h_e(i-1);] ...
        - [gps.lat(j); gps.lon(j); gps.h(j);]) + (DCMbn_n * gps.larm);
    
    zv = (vel_e (i-1,:) - gps.vel(j,:))';
    
    z = [ zv' zp' ]';
    
    %% KALMAN FILTER
    
    % GPS period
    dtg = tg(j) - tg(j-1);
    
    % Vector to update matrix F
    upd = [vel_e(i-1,:) lat_e(i-1) h_e(i-1) fn'];
    
    % Update matrices F and G
    [S.F, S.G] = F_update(upd, DCMbn_n, imu);
    
    % Update matrix H
    S.H = [Z I Z   Z Z Z Z;
        Z Z Tpr Z Z Z Z; ];
    
    % Execute the extended Kalman filter
    [xu, S] = kalman(x, z, S, dtg);
    
    % Execute UD filter
    %     [xu, Up, dp] = ud_filter(x, y, F, H, G, Q, R, Up, dp, dtg);
    %     P = Up * diag(dp) * Up';
    
    %% INS/GPS CORRECTIONS
    
    % DCM correction
    E = skewm(xu(1:3));
    DCMbn = (eye(3) + E) * DCMbn_n;
    
    % Quaternion corrections
    antm = [0 qua_n(3) -qua_n(2); -qua_n(3) 0 qua_n(1); qua_n(2) -qua_n(1) 0];
    qua = qua_n + 0.5 .* [qua_n(4)*eye(3) + antm; -1.*[qua_n(1) qua_n(2) qua_n(3)]] * xu(1:3);
    qua = qua/norm(qua);       % Brute force normalization
    
    % Attitude corrections
    roll_e(i-1)  = roll_e(i-1)  - xu(1);
    pitch_e(i-1) = pitch_e(i-1) - xu(2);
    yaw_e(i-1)   = yaw_e(i-1)   - xu(3);
    
    % Velocity corrections
    vel_e (i-1,1) = vel_e (i-1,1) - xu(4);
    vel_e (i-1,2) = vel_e (i-1,2) - xu(5);
    vel_e (i-1,3) = vel_e (i-1,3) - xu(6);
    
    % Position corrections
    lat_e(i-1) = lat_e(i-1) - double(xu(7));
    lon_e(i-1) = lon_e(i-1) - double(xu(8));
    h_e(i-1)   = h_e(i-1)   - xu(9);
    
    % Biases corrections
    gb_fix = gb_fix - xu(10:12);
    ab_fix = ab_fix - xu(13:15);
    gb_drift = gb_drift - xu(16:18);
    ab_drift = ab_drift - xu(19:21);
    
    % Matrices for later INS/GPS performance analysis
    X(j,:)   = xu';
    P_d(j,:) = diag(S.P)';
    Inn(j,:) = z';
    B(j,:)   = [gb_fix', ab_fix', gb_drift', ab_drift'];    
    
end
% Estimates from INS/GPS procedure
ins_gps_e.t     = ti(1:i-1, :);       % IMU time
ins_gps_e.roll  = roll_e(1:i-1, :);   % Roll
ins_gps_e.pitch = pitch_e(1:i-1, :);  % Pitch
ins_gps_e.yaw   = yaw_e(1:i-1, :);    % Yaw
ins_gps_e.vel   = vel_e(1:i-1, :);    % NED velocities
ins_gps_e.lat   = lat_e(1:i-1, :);    % Latitude
ins_gps_e.lon   = lon_e(1:i-1, :);    % Longitude
ins_gps_e.h     = h_e(1:i-1, :);      % Altitude
ins_gps_e.P_d   = P_d;                % P matrix diagonals
ins_gps_e.B     = B;                  % Kalman filter biases compensations
ins_gps_e.Inn   = Inn;                % Kalman filter innovations
ins_gps_e.X     = X;                  % Kalman filter states evolution
end
