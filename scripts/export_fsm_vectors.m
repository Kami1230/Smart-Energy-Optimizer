% Export simulink signlals to Q8.8 hex filed for $readmemh
modelName   = 'SmartEnergyOptimizer';
TS          = 0.1;                              %s, reseample period
scale       = 256;                              % Q8.8 scaling factor
outDir      = fullfile('repoRoot', 'vectors');    % Output directory for hex files

if ~exist(outDir, 'dir'), mkdir(outDir); end

out = sim(modelName);

% Name in workspace -> output file
signals = {
    'Surplus',      'vec_surplus.hex';
    'SoC',          'vec_soc.hex';
    'Battery_cmd',  'vec_battery_cmd.hex';
};

% Common time grid so all files have the same number of lines
t0 = 0;
tEnd = out.tout(end);
tGrid = (t0:TS:tEnd); % (start:step:stop);

for k = 1:size(signals, 1)
    name = signals{k, 1};
    ts   = out.tout;                               % timeseries        
    ts   = resample(ts, tGrid);                    % linear interp onto grid
    x    = squeeze(ts.Data);                       % extract data from timeseries

    raw = round(x * scale);
    raw = max(min(raw, 32767), -32768);            % saturate to int16 range
    u   = typecast(int16(raw(:)), 'uint16');       % two's complement bit pattern

    fid = fopen(fullfile(outDir, signals{k, 2}), 'w');
    fprintf(fid, '%04X\n', u);
    fclose(fid);

    fprintf('%-12s -> %s (%d samples, min %.3f, max %.3f)\n', ...
        name, signals{k, 2}, numel(x), min(x), max(x));

end