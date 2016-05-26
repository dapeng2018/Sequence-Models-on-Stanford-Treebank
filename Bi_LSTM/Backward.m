function[grad]=Backward(batch,grad,parameter,lstms,all_c_t,lstms_r,all_c_t_r)
    N=size(batch.Word,1);
    T=batch.MaxLen;
    zeroState=zeroMatrix([parameter.hidden,N]);
    dh = cell(parameter.layer_num, 1);
    dc = cell(parameter.layer_num, 1);
    for ll=1:parameter.layer_num    
        grad.W{ll}=zeroMatrix(size(parameter.W{ll}));
        grad.V{ll}=zeroMatrix(size(parameter.W{ll}));
    end
    wordCount = 0;
    numInputWords=size(batch.Word,1)*size(batch.Word,2);
    allEmbGrads=zeroMatrix([parameter.dimension,numInputWords]);

    for ll=parameter.layer_num:-1:1 
        dh{ll} = zeroState;
        dc{ll} = zeroState;
    end
    for t=T:-1:1
        unmaskedIds=batch.Left{t};
        for ll=parameter.layer_num:-1:1
            if t==T &&ll==parameter.layer_num
                dh{ll}=grad.grad_ht(1:parameter.hidden,:);
            end
            if t==1 c_t_1=[];
            else c_t_1 = all_c_t{ll, t-1};
            end
            c_t=all_c_t{ll, t};
            lstm = lstms{ll, t};
            W=parameter.W{ll};
            [lstm_grad]=lstmUnitGrad(W,lstm, c_t, c_t_1, dc{ll}, dh{ll},ll, t,zeroState,parameter);
            dc{ll} = lstm_grad.dc;
            dh{ll} = lstm_grad.input(end-parameter.hidden+1:end, :);
            grad.W{ll}=grad.W{ll}+lstm_grad.W;
            if ll==1
                embIndices=batch.Word(unmaskedIds,t)';
                embGrad = lstm_grad.input(1:parameter.dimension,unmaskedIds);
                numWords = length(embIndices);
                allEmbIndices(wordCount+1:wordCount+numWords) = embIndices;
                allEmbGrads(:, wordCount+1:wordCount+numWords) = embGrad;
                wordCount = wordCount + numWords;
            else
                dh{ll-1}(:,unmaskedIds)=dh{ll-1}(:,unmaskedIds)+lstm_grad.input(1:parameter.hidden,unmaskedIds,:);
            end
        end
    end
    allEmbGrads(:, wordCount+1:end) = [];
    allEmbIndices(wordCount+1:end) = [];
    [grad.W_emb, grad.indices] = aggregateMatrix(allEmbGrads, allEmbIndices);

    allEmbGrads=zeroMatrix([parameter.dimension,numInputWords]);
    for ll=parameter.layer_num:-1:1 
        dh{ll} = zeroState;
        dc{ll} = zeroState;
    end
    for t=T:-1:1
        unmaskedIds=batch.Left{t};
        for ll=parameter.layer_num:-1:1
            if t==T &&ll==parameter.layer_num
                dh{ll}=grad.grad_ht(parameter.hidden+1:2*parameter.hidden,:);
            end
            if t==1 c_t_1=[];
            else c_t_1 = all_c_t_r{ll, t-1};
            end
            c_t=all_c_t_r{ll, t};
            lstm = lstms_r{ll, t};
            W=parameter.V{ll};
            [lstm_grad]=lstmUnitGrad(W,lstm, c_t, c_t_1, dc{ll}, dh{ll},ll, t,zeroState,parameter);
            dc{ll} = lstm_grad.dc;
            dh{ll} = lstm_grad.input(end-parameter.hidden+1:end, :);
            grad.V{ll}=grad.V{ll}+lstm_grad.W;
            if ll==1
                embIndices=batch.Word_r(unmaskedIds,t)';
                embGrad = lstm_grad.input(1:parameter.dimension,unmaskedIds);
                numWords = length(embIndices);
                allEmbIndices(wordCount+1:wordCount+numWords) = embIndices;
                allEmbGrads(:, wordCount+1:wordCount+numWords) = embGrad;
                wordCount = wordCount + numWords;
            else
                dh{ll-1}(:,unmaskedIds)=dh{ll-1}(:,unmaskedIds)+lstm_grad.input(1:parameter.hidden,unmaskedIds,:);
            end
        end
    end

    clear dc;
    clear dh;
    allEmbGrads(:, wordCount+1:end) = [];
    allEmbIndices(wordCount+1:end) = [];
    [grad.W_emb_r, grad.indices_r] = aggregateMatrix(allEmbGrads, allEmbIndices);
    clear allEmbGrads;
    clear allEmbIndices;
    grad.W_emb=grad.W_emb+grad.W_emb_r;

    for ll=1:parameter.layer_num
        grad.W{ll}=grad.W{ll}/N;
        grad.V{ll}=grad.V{ll}/N;
    end
    grad.W_emb=grad.W_emb/N;
    grad.U=grad.U/N;
end


function[lstm_grad]=lstmUnitGrad(W,lstm, c_t, c_t_1, dc, dh, ll, t, zero_state,parameter)
    dc =arrayfun(@plusTanhPrimeTriple,dc,lstm.f_c_t,lstm.o_gate, dh);
    %dc = arrayfun(@plusMult, dc, lstm.o_gate, dh);
    do = arrayfun(@sigmoidPrimeTriple, lstm.o_gate, lstm.f_c_t, dh);
    di = arrayfun(@sigmoidPrimeTriple, lstm.i_gate, lstm.a_signal, dc);

    if t>1 
        df = arrayfun(@sigmoidPrimeTriple, lstm.f_gate, c_t_1, dc);
    else 
        df = zero_state;
    end
    lstm_grad.dc = lstm.f_gate.*dc;
    dl = arrayfun(@tanhPrimeTriple, lstm.a_signal, lstm.i_gate, dc);
    d_ifoa = [di; df; do; dl];
    lstm_grad.W = d_ifoa*lstm.input'; %dw
    lstm_grad.input = W'*d_ifoa;
    if parameter.dropout~=0
        lstm_grad.input=lstm_grad.input.*lstm.drop_left;
    end
    clear dc; clear do; clear di; clear df; clear d_ifoa;
end


function [value] = plusTanhPrimeTriple(t, x, y, z)
    value = t + (1-x*x)*y*z;
end
function [value] = tanhPrimeTriple(x, y, z)
    value = (1-x*x)*y*z;
end
function [value] = plusMult(x, y, z)
    value = x + y*z;
end
function [value] = sigmoidPrimeTriple(x, y, z)
    value = x*(1-x)*y*z;
end

function [clippedValue] = clipBackward(x)
    if x>1000 clippedValue = single(1000);
    elseif x<-1000 clippedValue = single(-1000);
    else clippedValue =single(x);
    end
end
