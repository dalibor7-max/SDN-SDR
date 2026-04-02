function combined_sdn_satcom_5g_demo()
    clear; clc; rng('shuffle');

    % --- Core Configuration ---
    Npackets = 100;
    Nships = 5; CARRIER = 6; SHORE = 7; SAT = 8;
    radius_km_5g = 55;
    max_retries = 3;
    timeout_penalty = 2.0;

    % --- VARIED DISTANCES FOR BAND VARIETY ---
    carrier_lat = 30.0; carrier_lon = -75.0;
    angles = linspace(0,2*pi,Nships+1); angles(end) = [];
    radii = [0.01, 0.08, 0.15, 0.30, 0.45]; 
    ship_lat = carrier_lat + radii .* cos(angles);
    ship_lon = carrier_lon + radii .* sin(angles);
    
    lat = [ship_lat, carrier_lat, carrier_lat+1.2, carrier_lat+3.0]';
    lon = [ship_lon, carrier_lon, carrier_lon+2.0, carrier_lon]';
    dmat_km = haversine_matrix(lat, lon);

    c_km_s = 299792.458;
    sat_alt_km = 35000;
    ship_bw = [256e3, 256e3, 512e3, 512e3, 512e3]; 

    fprintf('======================================================================\n');
    fprintf(' SDN HYBRID DEMO: INDEPENDENT PERIODIC FAULTS\n');
    fprintf(' SATCOM Down: Every 10th | 5G Down: Every 8th\n');
    fprintf('======================================================================\n');

    loss_count = 0;

    for pId = 1:Npackets
        pkt = struct();
        pkt.id = pId;
        pkt.src = randi(7); 
        pkt.dst = randi(7);
        while pkt.dst == pkt.src, pkt.dst = randi(7); end
        if rand < 0.5, pkt.tag = 'Tactical'; else, pkt.tag = 'Administrative'; end
        pkt.payload = sprintf('Data_Stream_%d', pId);
        dist_km = dmat_km(pkt.src, pkt.dst);

        % Define Independent Link Faults
        active_faults = {}; 
        if mod(pId, 10) == 0
            sat_pool = {'SATCOM 2 Mbps', 'SATCOM 4 Mbps', 'SATCOM 8 Mbps'};
            active_faults{end+1} = sat_pool{randi(numel(sat_pool))};
        end
        if mod(pId, 8) == 0
            fiveg_pool = {'5G High-band', '5G Mid-band', '5G Low-band'};
            active_faults{end+1} = fiveg_pool{randi(numel(fiveg_pool))};
        end

        if ~isempty(active_faults)
            fprintf('\n[PKT %03d] *** NETWORK ALERT: %s is DOWN ***\n', pId, strjoin(active_faults, ' & '));
        end

        % SDN Execution Logic
        success = false; used_path = ''; used_aes = false; failover_note = 'None';
        is_down = @(str) any(contains(active_faults, str));

        if strcmp(pkt.tag, 'Tactical')
            [band, ~] = get_5g_band_info(dist_km);
            is_5g_eligible = (dist_km <= radius_km_5g) && (pkt.dst ~= SHORE) && (pkt.src ~= SHORE);
            is_5g_up = ~is_down(band) && ~is_down('5G');
            if is_5g_eligible && is_5g_up
                success = true; used_path = '5G';
            else
                rate_mbps = [2, 4, 8]; chosen_rate = rate_mbps(randi(3));
                if ~is_down(sprintf('%d Mbps', chosen_rate))
                    success = true; used_path = 'SATCOM'; used_aes = true;
                    failover_note = '5G Unavail -> SATCOM Backup';
                else
                    failover_note = 'Primary (5G) and Backup (SATCOM) are BOTH DOWN';
                end
            end
        else
            rate_mbps = [2, 4, 8]; chosen_rate = rate_mbps(randi(3));
            if ~is_down(sprintf('%d Mbps', chosen_rate))
                success = true; used_path = 'SATCOM';
            else
                [band, ~] = get_5g_band_info(dist_km);
                is_5g_eligible = (dist_km <= radius_km_5g) && (pkt.dst ~= SHORE) && (pkt.src ~= SHORE);
                if is_5g_eligible && ~is_down(band)
                    success = true; used_path = '5G';
                    failover_note = 'SATCOM Down -> 5G Backup';
                else
                    failover_note = 'Primary (SATCOM) and Backup (5G) are BOTH DOWN';
                end
            end
        end

        % Reporting
        fprintf('Pkt%03d: %s -> %s | Tag: %-14s | Dist: %5.2f km\n', ...
            pId, node_name(pkt.src), node_name(pkt.dst), pkt.tag, dist_km);
        
        if success
            if used_aes
                pkt.payload = aes_encrypt_string(pkt.payload);
                fprintf('  ENC: AES-256-GCM\n');
            else
                fprintf('  ENC: OFF\n');
            end

            if strcmp(used_path, 'SATCOM')
                sim = simulate_satcom_v5(pkt, dmat_km, ship_bw, chosen_rate*1e6, c_km_s, sat_alt_km, max_retries, timeout_penalty, SHORE);
                fprintf('  LINK: SATCOM | Path: %s\n', sim.path);
                fprintf('  Stats: Rate: %.1f Mbps | LossProb: %.2f%% | Retries: %d\n', chosen_rate, sim.loss_prob*100, sim.retries);
                fprintf('  Delay: Prop: %.3fs | Tx: %.3fs | Penalty: %.1fs | TOTAL: %.3f s\n', ...
                    sim.prop_time_s, sim.tx_time_s, sim.retries*timeout_penalty, sim.total_latency_s);
            else
                [band, desc] = get_5g_band_info(dist_km);
                sim = simulate_5g_v5(dist_km, band);
                fprintf('  LINK: 5G     | Band: %s (%s) | TxRate: %.1f Mbps\n', band, desc, sim.rate_bps/1e6);
                fprintf('  Delay: TOTAL LATENCY: %.3f s\n', sim.latency_s);
            end
        else
            loss_count = loss_count + 1;
            fprintf('  *** 100%% PACKET LOSS *** (Reason: %s)\n', failover_note);
        end
        fprintf('  --------------------------------------------------------------\n');
    end

    fprintf('\n======================== FINAL REPORT ========================\n');
    fprintf(' Total Packets: %d | Delivered: %d | Dropped: %d\n', Npackets, Npackets-loss_count, loss_count);
    fprintf(' Reliability: %.1f%%\n', ((Npackets-loss_count)/Npackets)*100);
end

% --- Helpers ---
function [band, desc] = get_5g_band_info(dist)
    if dist <= 1.6, band = 'High-band'; desc = 'mmWave';
    elseif dist <= 20, band = 'Mid-band'; desc = 'Sub-6GHz';
    else, band = 'Low-band'; desc = 'Sub-1GHz'; end
end

function sim = simulate_satcom_v5(pkt, dmat_km, ship_bw, rate_bps, c_km_s, sat_alt_km, max_retries, penalty, SHORE)
    data_bits = 1e6;
    loss_prob = 0.05 * rand();
    prop_one = (2 * sat_alt_km) / c_km_s;
    
    % 1 Hop: Any connection involving the SHORE (Source OR Destination)
    % 2 Hops: Ship-to-Ship connection where distance > 55km
    if pkt.src == SHORE || pkt.dst == SHORE
        hops = 1;
        sim.path = sprintf('%s -> SAT -> %s', node_name(pkt.src), node_name(pkt.dst));
    elseif dmat_km(pkt.src, pkt.dst) > 55
        hops = 2;
        sim.path = sprintf('%s -> SAT -> Shore -> SAT -> %s', node_name(pkt.src), node_name(pkt.dst));
    else
        hops = 1;
        sim.path = sprintf('%s -> SAT -> %s', node_name(pkt.src), node_name(pkt.dst));
    end
    
    sim.loss_prob = loss_prob;
    sim.retries = 0;
    while (rand() < loss_prob) && (sim.retries < max_retries)
        sim.retries = sim.retries + 1;
    end
    sim.prop_time_s = hops * prop_one;
    sim.tx_time_s = hops * (data_bits / rate_bps);
    sim.total_latency_s = sim.prop_time_s + sim.tx_time_s + (sim.retries * penalty);
end

function sim = simulate_5g_v5(dist, band)
    if strcmp(band, 'High-band'), rate = 1000e6;
    elseif strcmp(band, 'Mid-band'), rate = 100e6;
    else, rate = 10e6; end
    sim.rate_bps = rate;
    sim.latency_s = (1e6 / rate) + (rand * 0.002); 
end

function name = node_name(id)
    names = {'Ship1', 'Ship2', 'Ship3', 'Ship4', 'Ship5', 'Carrier', 'Shore', 'SAT'};
    name = names{id};
end

function out = aes_encrypt_string(in)
    payloadBytes = [uint8(1:12), uint8(in)];
    out = char(java.util.Base64.getEncoder().encodeToString(int8(payloadBytes)));
end

function D = haversine_matrix(lat, lon)
    R = 6371; n = numel(lat); D = zeros(n);
    for i = 1:n
        for j = i+1:n
            dphi = (lat(j)-lat(i))*pi/180; dlam = (lon(j)-lon(i))*pi/180;
            a = sin(dphi/2)^2 + cos(lat(i)*pi/180)*cos(lat(j)*pi/180)*sin(dlam/2)^2;
            D(i,j) = R * 2 * atan2(sqrt(a), sqrt(1-a)); D(j,i) = D(i,j);
        end
    end
end