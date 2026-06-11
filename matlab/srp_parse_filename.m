function info = srp_parse_filename(name)
%SRP_PARSE_FILENAME  Extract ageing conditions from a data file name.
%
%   info = SRP_PARSE_FILENAME(name) parses a name of the form
%       T<temp>_d<days>_v<strainRate>_s<sample>
%   (optionally with a path and/or extension) and returns a struct with
%   fields:
%       .temp_C       storage temperature           (deg C)
%       .days         ageing time                   (days)
%       .strain_rate  UTM cross-head speed          (mm/min)
%       .sample       replicate number
%       .name         the file's base name (no path/extension)
%       .valid        true if all four tokens were found
%
%   The parser is tolerant of upper/lower case and of decimal values, e.g.
%   "t50_d122_v500_s3", "T50_d122.5_v500_s3.csv" both parse.
%
%   Example:
%       info = srp_parse_filename('T60_d31_v50_s7.csv');

    [~, base, ext] = fileparts(char(name));
    if isempty(base) && ~isempty(ext)
        base = ext;   % handle names that are only an extension-like token
    end

    info = struct('temp_C', NaN, 'days', NaN, 'strain_rate', NaN, ...
                  'sample', NaN, 'name', base, 'valid', false);

    % Tolerant tokenised regex: <letter><number> groups separated by '_'.
    info.temp_C      = local_token(base, '[Tt]');
    info.days        = local_token(base, '[Dd]');
    info.strain_rate = local_token(base, '[Vv]');
    info.sample      = local_token(base, '[Ss]');

    info.valid = all(~isnan([info.temp_C, info.days, ...
                             info.strain_rate, info.sample]));
end

function val = local_token(str, letterClass)
%LOCAL_TOKEN  Return the number following <letter> in a token, else NaN.
    pat = [letterClass, '([+-]?\d+(?:\.\d+)?)'];
    tok = regexp(str, pat, 'tokens', 'once');
    if isempty(tok)
        val = NaN;
    else
        val = str2double(tok{1});
    end
end
