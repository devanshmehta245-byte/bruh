% service_life_arrhenius.m
% -------------------------------------------------------------------------
% Accelerated-aging service-life prediction for a solid propellant using an
% Arrhenius temperature-acceleration model combined with a power-law
% property-degradation (cumulative-damage) law.
%
% The script estimates, for a range of storage/service temperatures, the time
% required for a normalised mechanical property to decay from its initial
% value down to a defined failure threshold, and reports that service life
% in years.
% -------------------------------------------------------------------------

% Constants
Ea = 80000;        % Activation energy, J/mol
R  = 8.314;        % Universal gas constant, J/(mol*K)
T_service = 300.15; % Service (reference) temperature, K (27 deg C)
t_test = 60;       % Test duration, days
E_test = 1;        % Property measured after the test (normalised)
E_crit = 0.3;      % Failure threshold (fraction of initial property)
n = -0.4;          % Power-law model exponent

% Test temperatures in Celsius
temperatures_C = [25, 27, 30, 35, 40, 45, 50, 60, 70];
T_test = 273.15 + temperatures_C;   % Convert to Kelvin

% Prepare arrays to collect results
tf_days  = zeros(size(T_test));
tf_years = zeros(size(T_test));

for i = 1:length(T_test)
    % Arrhenius calculations
    A = E_test / (t_test ^ n);              % Pre-factor from the test point
    inv_T_service = 1 / T_service;
    inv_T_test    = 1 / T_test(i);
    X  = (Ea / R) * (inv_T_test - inv_T_service);
    AF = A * exp(X);                         % Acceleration factor

    % Service life
    tf = (E_crit / A) ^ (1 / n);            % Time to reach failure threshold
    t_service_eq = tf .* AF;                % Equivalent time at service T
    tf_days(i)  = tf;
    tf_years(i) = (t_service_eq / 365.25);
end

% Plotting
figure;
plot(temperatures_C, tf_years, '-s', 'DisplayName', 'Service Life (years)');
hold on;
xlabel('Temperature (\circC)');
ylabel('Service Life (years)');
title('Service Life vs Temperature');
legend('show');
grid on;
hold off;

table_service = table(temperatures_C', tf_years', ...
    'VariableNames', {'Temperatures', 'Service_Life'});
disp(table_service)
