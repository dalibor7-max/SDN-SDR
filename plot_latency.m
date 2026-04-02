%% plot_latency.m
clear; clc; close all;

data = final_v7();
latencyData = [ [data.avgL5g]', [data.avgLSat]' ];

figure('Color','w','Name','SDN Maritime Latency Analysis');
set(gca, 'XColor', 'k', 'YColor', 'k');
b = bar(latencyData, 'grouped');
b(1).FaceColor = [0 0.45 0.74]; % 5G Blue
b(2).FaceColor = [0.85 0.33 0.1]; % SATCOM Orange

set(gca, 'XTickLabel', {'1-10', '1-30', '1-75', '1-200', '1-500', '1-1000'});
ylabel('Mean Latency (ms)');
xlabel('Packet Range');
title('Mean Latency: Multi-Tier 5G vs SATCOM');
legend({'5G', 'SATCOM'}, 'Location', 'northeastoutside');
grid on;

% Add value labels on top of bars
for i = 1:numel(b)
    xtips = b(i).XEndPoints; ytips = b(i).YData;
    labels_text = string(round(ytips, 1)) + " ms";
    text(xtips, ytips, labels_text, 'HorizontalAlignment','center',...
         'VerticalAlignment','bottom', 'FontSize', 8, 'FontWeight','bold');
end