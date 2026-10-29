function abq = readAbaqusResults(folder)
% Load the text files written by abaqus/read_odb.py.
abq = struct('frequencyHz',[],'generalizedMass',[],'nodes',[],'Phi',[], ...
    'ssd',[],'impact',[]);
f = fullfile(folder,'frequencies.txt');
if isfile(f)
    F = readmatrix(f,FileType='text');
    abq.frequencyHz = F(:,2); abq.generalizedMass = F(:,3);
    abq.nodes = readmatrix(fullfile(folder,'modes_nodes.txt'),FileType='text');
    U = readmatrix(fullfile(folder,'modes_u.txt'),FileType='text');
    % Rows: nodes; columns: [U1 U2 U3] per mode -> component-blocked DOFs.
    nm = size(U,2)/3; n = size(U,1);
    abq.Phi = zeros(3*n,nm);
    for k = 1:nm
        abq.Phi(:,k) = reshape(U(:,3*k-2:3*k),[],1);
    end
end
f = fullfile(folder,'ssd.txt');
if isfile(f)
    S = readmatrix(f,FileType='text');
    abq.ssd = struct('frequencyHz',S(:,1),'U',S(:,2:4)+1i*S(:,5:7));
end
f = fullfile(folder,'impact.txt');
if isfile(f)
    T = readmatrix(f,FileType='text');
    abq.impact = struct('time',T(:,1),'displacement',T(:,2),'acceleration',T(:,3));
end
end
