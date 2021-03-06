% This file is part of LCToolbox.
% (c) Copyright 2018 - MECO Research Team, KU Leuven. 
%
% LCToolbox is free software: you can redistribute it and/or modify
% it under the terms of the GNU Lesser General Public License as published 
% by the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% LCToolbox is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU Lesser General Public License for more details.
% 
% You should have received a copy of the GNU Lesser General Public License
% along with LCToolbox. If not, see <http://www.gnu.org/licenses/>.

clear all
close all
clc

%% 1. Goal
% The goal of this tutorial is to design a controller based on an
% H-infinity formalism. Depending on the type of constraints we impose, a
% different solver is most suited and will therefore be picked by the
% toolbox.

%% 2. System declarations
% Plant
Gmod = ZPKmod([-16+720j, -16-720j],[-1100, 190, -160, -18+770j, -18-770j],1e8);

% Weights
MS = Weight.DC(10);          % Maximum on sensitivity: 8dB
WS = Weight.LF(20,1,-40);   % Weight on sensitivity to assure roll-off
WSu = Weight.LF(20,1);
WU = Weight.HF(2e3,1,-5);  % Weight on input sensitivity to assure roll-off on the controller

%% 3. Controller design
G = IOSystem(1,1);
G.add(Gmod);
K = IOSystem(1,1);  

r = Signal();
u = G.in;
y = G.out;
e = r - y;
connections = [K.in == e; K.out == u];
P = IOSystem(G,K,connections);

% Classical stable WS vs. unstable WS (implemented in mixedHinfsynMIMO)
S = Channel(e/r, 'Sensitivity');
U = Channel(u/r, 'Input Sensitivity');

objective = WS*S;
constraints = [WU*U <= 1, MS*S <= 1];
options = struct('controller_name','mixed\_controller');
[P,C1,info1] = P.solve(objective, constraints, K, options);

objective = WSu*S;
constraints = [WU*U <= 1, MS*S <= 1];
options = struct('controller_name','mixed\_controller\_unstable','gammasolver','mosek');
[P,C2,info2] = P.solve(objective, constraints, K, options);

figure, bodemag(info1,info2,S,U) %show CL performance
figure, bode(K) %show controller

%% 4. Discussion
% The low frequency pole in WS that was still necessary to solve the 
% problem with mixedHinfsyn is superfluous when solving with
% mixedHinfsynMIMO. The latter is able to solve also problems with improper
% weights, making it possible to use a pure integrator as sensitivity
% weight. This also results in a pure integrator in the controller.
%
% No manual shifting of the low-freqency poles to the origin is required,
% making this a very nice solver (if it is numerically well conditioned of 
% course.)