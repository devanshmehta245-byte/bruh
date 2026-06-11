function srp_plot_results(D, A, model, res, cfg)
%SRP_PLOT_RESULTS  Visualise degradation, ML fit, Arrhenius line & service life.
%
%   srp_plot_results(D, A, model, res, cfg) creates and saves figures into
%   cfg.resultsDir:
%       1) health property vs ageing time, per temperature, with kinetic fits
%       2) ML predicted vs measured (parity plot)
%       3) Arrhenius plot ln(t_fail) vs 1/T with service-temperature point
%
%   Plotting is wrapped in try/catch so a headless environment cannot break
%   the numerical pipeline.

    if nargin < 5 || isempty(cfg); cfg = srp_config(); end
    if ~exist(cfg.resultsDir, 'dir'); mkdir(cfg.resultsDir); end
    prop = cfg.healthProperty;

    % ----------------------------------------- 1) degradation curves + fits
    try
        fig = local_new_fig();
        hold on;
        temps = res.temps_C;
        colors = lines(numel(temps));
        hLeg = zeros(numel(temps), 1);
        labels = cell(numel(temps), 1);
        for i = 1:numel(temps)
            T = temps(i);
            m = (A.temp_C == T) & (A.strain_rate == cfg.referenceStrainRate);
            tt = A.days(m); pp = A.mean.(prop)(m); ss = A.std.(prop)(m);
            [tt, ord] = sort(tt); pp = pp(ord); ss = ss(ord);
            local_errorbar(tt, pp, ss, colors(i, :));
            tg = linspace(0, max(tt) * 1.1, 100);
            hLeg(i) = plot(tg, res.Pfun(tg, T), '-', 'Color', colors(i, :), ...
                'LineWidth', 1.8);
            labels{i} = sprintf('%g \\circC', T);
        end
        yline_compat(res.P_fail, 'k--', 'P_{fail}');
        xlabel('ageing time (days)');
        ylabel(strrep(prop, '_', '\_'));
        title('Health property vs ageing time (reference strain rate)');
        legend(hLeg, labels);
        grid on; box on;
        local_save(fig, fullfile(cfg.resultsDir, 'degradation_curves.png'));
    catch err
        warning('srp_plot_results:fig1', '%s', err.message);
    end

    % ----------------------------------------- 2) ML parity plot
    try
        y = D.Y.(cfg.mlTarget);
        yhat = model.predictFcn(D.X);
        good = isfinite(y) & isfinite(yhat);
        fig = local_new_fig();
        plot(y(good), yhat(good), 'o'); hold on;
        lim = [min([y(good); yhat(good)]), max([y(good); yhat(good)])];
        plot(lim, lim, 'k--');
        axis equal; xlim(lim); ylim(lim);
        xlabel('measured'); ylabel('ML predicted');
        title(sprintf('ML model "%s": %s (CV-R^2=%.3f)', ...
            model.name, strrep(cfg.mlTarget, '_', '\_'), model.cvR2));
        grid on; box on;
        local_save(fig, fullfile(cfg.resultsDir, 'ml_parity.png'));
    catch err
        warning('srp_plot_results:fig2', '%s', err.message);
    end

    % ----------------------------------------- 3) Arrhenius plot
    try
        if isfield(res, 'arrheniusSlope') && isfinite(res.arrheniusSlope)
            fig = local_new_fig();
            TK = res.temps_C + 273.15;
            x = 1 ./ TK; ylog = log(res.tfail_used);
            plot(x, ylog, 'o', 'MarkerFaceColor', 'b'); hold on;
            Ts = cfg.serviceTemp_C + 273.15;
            xg = linspace(min([x; 1/Ts]), max([x; 1/Ts]), 50);
            plot(xg, res.arrheniusIntercept + res.arrheniusSlope * xg, 'r-');
            plot(1/Ts, log(res.serviceLife_days), 'rs', ...
                'MarkerFaceColor', 'r', 'MarkerSize', 10);
            xlabel('1/T (1/K)'); ylabel('ln(t_{fail} / days)');
            title(sprintf('Arrhenius: E_a=%.1f kJ/mol, service life=%.0f d (%.1f yr) @ %g \\circC', ...
                res.Ea_kJmol, res.serviceLife_days, res.serviceLife_years, ...
                cfg.serviceTemp_C));
            grid on; box on;
            local_save(fig, fullfile(cfg.resultsDir, 'arrhenius.png'));
        end
    catch err
        warning('srp_plot_results:fig3', '%s', err.message);
    end
end

% ------------------------------------------------------------------ helpers
function fig = local_new_fig()
    try
        fig = figure('Visible', 'off');
    catch
        fig = figure();
    end
end

function local_save(fig, fname)
    try
        print(fig, fname, '-dpng', '-r120');
    catch
        try, saveas(fig, fname); catch; end
    end
    try, close(fig); catch; end
end

function local_errorbar(x, y, e, col)
    e(~isfinite(e)) = 0;
    try
        errorbar(x, y, e, 'o', 'Color', col, 'MarkerFaceColor', col);
    catch
        plot(x, y, 'o', 'Color', col, 'MarkerFaceColor', col);
    end
end

function yline_compat(yv, style, label)
    xl = xlim;
    try
        plot(xl, [yv yv], style, 'HandleVisibility', 'off');
        text(xl(1), yv, [' ' label], 'VerticalAlignment', 'bottom');
    catch
    end
end
