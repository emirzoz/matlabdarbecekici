function deg = parseLayup(text)
% Ply angles (degrees, first = bottom ply) from layup notation:
%   "0/45/-45/90"   "[0/±45/90]s"   "[0/90]2s"   "[+-45]3"   "0/90/0"
% ± (or +-) expands to +a/-a; "s" mirrors the stack; a number repeats it
% (before "s": repeat then mirror).
s = strrep(strrep(strtrim(char(text)),'±','+-'),' ','');
tok = regexp(s,'^\[?([^\]]*)\]?(\d*)(s?)$','tokens','once','ignorecase');
assert(~isempty(tok) && ~isempty(tok{1}),'vil:Layup','Layup "%s" not understood. Example: [0/45/-45/90]s.',text);
deg = [];
for item = strsplit(tok{1},'/')
    v = item{1};
    if startsWith(v,'+-')
        a = str2double(v(3:end)); deg = [deg a -a]; %#ok<AGROW>
    else
        a = str2double(v); deg = [deg a]; %#ok<AGROW>
    end
    assert(all(isfinite(deg)),'vil:Layup','Ply angle "%s" is not a number.',v);
end
if ~isempty(tok{2}), deg = repmat(deg,1,str2double(tok{2})); end
if ~isempty(tok{3}), deg = [deg flip(deg)]; end
end
