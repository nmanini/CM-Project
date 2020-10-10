%{
    Modified version of the main algorithm which computes and returns 
    the difference from the final approximation at each iteration, this is
    done to get some insights on the execution
    
%}

function [U,V, it, errs, gradnorms, rate_err] = LowRankAlgo_Rate(A, k, max_it, err_eps, grad_eps, stop_c_type, init_t, init_w, printsteps)

arguments
end


arguments
    A (:,:) {mustBeNumeric}
    k (1,1) {mustBeNumeric}
    max_it (1,1) {mustBeNumeric} = DefaultValue('max_it')
    err_eps (1,1) {mustBeNumeric} = DefaultValue('err_eps')
    grad_eps (1,1) {mustBeNumeric} = DefaultValue('grad_eps')
    stop_c_type = DefaultValue('stop_c_type')
    init_t = DefaultValue('init_t')
    init_w = DefaultValue('init_w')
    printsteps = DefaultValue('printsteps')
end

if strcmp(stop_c_type, 'default')
    stop_c_type = DefaultValue('stop_c_type');
end
if strcmp(init_t, 'default')
    init_t = DefaultValue('init_t');
end
if strcmp(init_w, 'default')
    init_w = DefaultValue('init_w');
end

[m,n] = size(A);
na = norm(A, 'fro');

% A can't be approximated with a matrix of greater of equal rank
if k >= min(m,n) || k < 1
    error('k must be between 1 and the rank of A')
end

% Initialization of V
V = PickInitialMatrix(init_t, k, n, na);

find = 0;
prevErr = realmax();
%relDiff = realmax();

it = 0;
stopCond = true;
final_log = "";

% Save the current scores
errs = zeros(max_it + 1, 1);
gradnorms = zeros(max_it + 1, 1);
UVs = zeros(m,n,max_it+1);

while stopCond
    it = it + 1;
    if printsteps == 2 
        fprintf(" ========= Iteration %d\n", it);
    end
    
    if find == 0 % Find U
        U = transpose(SubTask(transpose(A), transpose(V), init_w));
        find = 1;
    else         % Find V
        V = SubTask(A,U,init_w);
        find = 0;   
    end
    
    % Check for termination
    [term, curErr, relDiff, ng] = TerminationCheck(                     ...
                            stop_c_type, max_it, err_eps, grad_eps,     ...
                            A, U, V, it, prevErr);
   
    prevErr = curErr;
    stopCond = not(term);
    
    errs(it) = curErr/na;
    gradnorms(it) = ng;
    UVs(:,:,it) = U*V;
                        
    if printsteps == 2
        l = PrintLog(relDiff, ng, stop_c_type);
        final_log = l;
        fprintf("%s\n", l);
    end    
end
if printsteps > 0
    fprintf("Number of iterations: %d\n", it);
    fprintf("===== Final error values =====\n");
    fprintf("%s", final_log);
end


Ares = U*V;
rate_err = zeros(it, 1);

for i=1:it
    rate_err(i) = norm(Ares - UVs(:,:,i));
end

% Trim the resulting vectors
errs = errs(1:min(it, max_it));
gradnorms = gradnorms(1:min(it, max_it));
end

function [Z] = SubTask(A,Y,init_w)
    [Q, R, P, kr] = MyQRP(Y);
    [~,k] = size(Y);
    [~,n] = size(A);
    R11 = R(1:kr, 1:kr);
    R12 = R(1:kr, kr+1:k);
    Ztmp = zeros(k,n);
    for i=1:n % Compute the i-th column of Z
        % Pick the vector w
        w = PickW(init_w, k-kr);
        
        btmp = transpose(Q) * A(:,i);
        b = btmp(1:kr);
        t = -R12*w;
        t = t + b;
        ztmp = zeros(k,1);
        y = R11 \ t;
        ztmp(1:kr) = y;
        ztmp(kr+1:k) = w;
        zi = P * ztmp;
        Ztmp(:,i) = zi; 
    end
    Z = Ztmp;
end


function [term, cur_err, rel_diff, ng] = TerminationCheck(stop_t, maxit, err_t, grad_t, A, U, V, iter, prev_err)
    X = U*V;
    cur_err = -1;
    rel_diff = -1;
    ng = -1;
    
    term = true;
    if iter > maxit
        return
    end
    
    % If set to true then the algorithm will compute and log all stop metrics
    LogAllMetrics = true;
    
    need_err = LogAllMetrics;
    term_err = false;
    need_grad = LogAllMetrics;
    term_grad = false;
    
    switch stop_t
        case 'approxerror'
            need_err = true;
        case 'approxerror2'
            need_err = true;
        case 'gradientnorm'
            need_grad = true;
        case 'both'
            need_err = true;
            need_grad = true;
        case 'any'
            need_err = true;
            need_grad = true;
    end
    
    if need_err 
        cur_err = ApproxError(A,X);
        rel_diff = abs(prev_err - cur_err) / prev_err;
        term_err = (rel_diff <= err_t);
        norm_diff = abs(prev_err - cur_err) / norm(A, 'fro');
        term_norm_err = (norm_diff <= err_t);
    end
    
    if need_grad
        ng = GradientNorm(A,X,U,V);
        term_grad = (ng <= grad_t);
    end
    
    switch stop_t
        case 'approxerror'
            term = term_err;
        case 'approxerror2'
            term = term_norm_err;
        case 'gradientnorm'
            term = term_grad;
        case 'both'
            term = term_err && term_grad;
        case 'any'
            term = term_err || term_grad;
    end
    
end

function [s] = PrintLog(ae, ng, t)
    ae_s = sprintf("Relative approximation error: %d\n", ae);
    ng_s = sprintf("Gradient norm: %d\n", ng);
    switch t
        case 'approxerror'
            s = ae_s;
        case 'approxerror2'
            s = ae_s;
        case 'gradientnorm'
            s = ng_s;
        case 'both'
            s = strcat(ae_s, ng_s);
        case 'any'
            s = strcat(ae_s, ng_s);
    end
end

function [V] = PickInitialMatrix(logic, m, n, nn)
switch logic
    case 'random'
        V = nn * randn(m,n);
    case 'randfull'
        V = nn * RandRank(m, n, m);
    case 'eye'
        V = eye(m,n);
    case 'randeye'
        V = zeros(m,n);
        V(:, 1:m) = nn * diag(rand(m, 1));
    case 'eyedistinct'
        V = EyeExtended(m,n, true);
    case 'eyeextended'
        V = EyeExtended(m,n, false);
    otherwise
        error('initialization type not supported')
end
end

function [w] = PickW(logic, len)
switch logic
    case 'zeros'
        w = zeros(len, 1);
    case 'ones'
        w = ones(len, 1);
    case 'rand'
        w = randn(len, 1);
    otherwise
        error('Initialization of w not supported');
end
end
