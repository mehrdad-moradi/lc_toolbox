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

classdef Solver_mixedHinfsynMIMO < Solver
% Solver_mixedHinfsynMIMO defines a solver interface for \c mixedHinfsynMIMO.
        
    methods
        function self = Solver_mixedHinfsynMIMO(options)
        % Constructor for Channel objects.
        % 
        % Parameters:
        %  options: options that the user wants to pass to the solver
        %
        % Return values:
        %  self: the solver interface @type Solver_mixedHinfsynMIMO 
        
            % Solver
            fprintf('Solving with mixedHinfsynMIMO...\n\n');
            
            % Default options
            self.options.gammasolver.solver = 'mosek';
            self.options.gammasolver.mosek.MSK_DPAR_ANA_SOL_INFEAS_TOL = 1e-8;
            self.options.controllersolver.solver = 'basiclmi';

            if nargin > 0
                self = setoptions(self,options);
            end
        end
        
        function self = solve(self,config,specs,vars)
        % Parses all available information of the interface, calls the 
        % solver \c mixedHinfsynMIMO and saves the results.
        % 
        % Parameters:
        %  self: the solver interface @type Solver_mixedHinfsynMIMO
        %  config: the control configuration @type SystemOfSystems
        %  specs: specifications of the control problem @type
        %  ControllerDesign
        %  vars: \c cell containing the optimization variables @type cell
        %
        % Return values:
        %  self: solver interface containing the solution (if properly
        %  solved) and, if available, additional information @type
        %  Solver_mixedHinfsynMIMO
        
            % Get output filters
            specs = rescale(specs,'all');
            [P,Wo,Wi,ch] = Solver_mixedHinfsynMIMO.plant(config,specs,vars);
    
            % Setup which channels are objectives and which are constraints
            alpha = zeros(1,length(specs.performance)); 
            alpha(1,1:specs.nobj) = 1;
            
            % Get number of controls and measurements
            ncont = length(specs.ctrl_in);
            nmeas = length(specs.ctrl_out);

            tic;
            stdP = std(P);
            if isnumeric(Wo); Wo = ss(Wo); Wo.Ts = stdP.Ts; else; Wo = std(Wo); end
            if isnumeric(Wi); Wi = ss(Wi); Wi.Ts = stdP.Ts; else; Wi = std(Wi); end
            [K, gamma, ~] = mixedHinfsynMIMO(stdP,Wi,Wo,nmeas,ncont,alpha,double(~alpha),ch,self.options);
            self.info.time = toc;
            self.K = fromstd(K);
            self.gamma = transpose(gamma(:,1)); 
            self.mu = zeros(size(gamma)); 
            self.solved = true;
            
            % rescale performance weights
            self.performance = specs.performance;
            if specs.nobj > 0
                obj = 1:specs.nobj;
                self.performance(obj) = self.performance(obj).*transpose(1./gamma(obj,2));
            end
        end
    end
    
    methods (Static)
        function [P,Wo,Wi,ch] = plant(config,specs,vars)
        % Parses the generalized plant in the form that is required by
        % \c mixedHinfsynMIMO. 
        % 
        % Parameters:
        %  config: the control configuration @type SystemOfSystems
        %  specs: specifications of the control problem @type
        %  ControllerDesign
        %  vars: \c cell containing the optimization variables @type cell
        %
        % Return values:
        %  P: generalized plant @type numlti
        %  Wo: unstable output weighting filter @type numlti
        %  Wi: unstable input weighting filter @type numlti
        %  ch: structure defining the channels corresponding to the
        %  specifications @type struct
        
            Wo = [];
            Wi = [];
            stabspecs = specs;
            
            % Set up unstable weights
            for k = 1:length(specs.performance)
                
                [GSo,GNSo] = stabsep(fromstd(specs.performance(k).W_out));
                [GSi,GNSi] = stabsep(fromstd(specs.performance(k).W_in));
                if GNSo.nx == 0 % stable weight
                    Wo = blkdiag(Wo,eye(size(specs.performance(k).W_out,1)));
                elseif GSo.nx == 0 % unstable weight
                    Wo = blkdiag(Wo,specs.performance(k).W_out);
                    stabspecs.performance(k).W_out = eye(size(specs.performance(k).W_out,1));
                else
                    error('One of your output weights contains both stable and unstable poles, which I cannot separate. Make all poles unstable in case you want a weight with integrators and make all poles stable otherwise.')
                end
                if GNSi.nx == 0
                    Wi = blkdiag(Wi,eye(size(specs.performance(k).W_in,1)));
                elseif GSi.nx == 0
                    Wi = blkdiag(Wi,specs.performance(k).W_in);
                    stabspecs.performance(k).W_in = eye(size(specs.performance(k).W_in,1));
                else
                    error('One of your input weights contains both stable and unstable poles, which I cannot separate. Make all poles unstable in case you want a weight with integrators and make all poles stable otherwise.')
                end
            end
                
            [P,wspecs] = Solver.plant(config,stabspecs,vars,false);
            
            ch = Solver.channels(wspecs);   
            for i = 1:length(ch.In)
                [r,~] = find(ch.In{i});
                [~,c] = find(ch.Out{i});
                channels(i).In = r';
                channels(i).Out = c';
            end
            ch = channels;
        end
        
        function cap = capabilities()
        % Returns the capabilities of \c mixedHinfsynMIMO. 
        % 
        % Return values: 
        %  cap: capabilities of \c mixedHinfsynMIMO @type struct
        
            cap.inout = 2;
            cap.norm = Inf;
            cap.constraints = true;
            cap.unstable = true;
            cap.improper = false;
            cap.parametric = false;
            cap.fixedorder = false;
        end
    end
end

