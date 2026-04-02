function batchResults = final_v7()
    
    clear; clc; rng('shuffle');

    intervals = [10, 30, 75, 200, 500, 1000]; 
    maxPkt = max(intervals);
    batchResults = struct();
    
    radius_km_5g = 55; % 5G Range
    c_km_s = 299792.458; sat_alt_km = 35000;
    SHORE = 7;
    

    carrier_lat = 30.0; carrier_lon = -75.0;
    angles = linspace(0,2*pi,5+1); angles(end) = [];
    radii = [0.01, 0.08, 0.15, 0.30, 0.45];
    ship_lat = carrier_lat + radii .* cos(angles);
    ship_lon = carrier_lon + radii .* sin(angles);
    
    lat = [ship_lat, carrier_lat, carrier_lat+1.2, carrier_lat+3.0]';
    lon = [ship_lon, carrier_lon, carrier_lon+2.0, carrier_lon]';
    
   
    dmat_km = zeros(8);
    R = 6371;
    for i=1:8
        for j=1:8
            dphi = deg2rad(lat(j)-lat(i)); dlam = deg2rad(lon(j)-lon(i));
            a = sin(dphi/2)^2 + cos(deg2rad(lat(i)))*cos(deg2rad(lat(j)))*sin(dlam/2)^2;
            dmat_km(i,j) = R * 2 * atan2(sqrt(a), sqrt(1-a));
        end
    end

    all_l5g = []; all_lSat = [];
    
    for pId = 1:maxPkt
        src = randi(7); dst = randi(7); while dst == src, dst = randi(7); end
        dist_km = dmat_km(src, dst);
        fault5G = (mod(pId, 8) == 0); faultSat = (mod(pId, 10) == 0);

        % SDN Logic
        if dist_km <= radius_km_5g && ~fault5G && dst ~= SHORE && src ~= SHORE
            % 5G Path
            if dist_km <= 1.6, rate = 1000e6;      % High-band
            elseif dist_km <= 20, rate = 100e6;    % Mid-band
            else, rate = 10e6;                     % Low-band
            end
            
            lat_ms = ((1e6 / rate) + (rand * 0.002)) * 1000; 
            all_l5g(end+1) = lat_ms;
        else
            % SATCOM Path 
            if ~faultSat
                prop_one = (2 * sat_alt_km) / c_km_s;
                
                % Determine if Double-Hop is needed
                if src ~= SHORE && dst ~= SHORE && dist_km > 55
                    hops = 2;
                else
                    hops = 1;
                end
                
                retries = 0; while rand < 0.05 && retries < 3, retries = retries + 1; end
                
                % Delay = (Hops * Prop) + (Hops * Tx) + (Retries * Penalty)
                lat_sec = (hops * prop_one) + (hops * (1e6/4e6)) + (retries * 2.0);
                all_lSat(end+1) = lat_sec * 1000;
            end
        end

        if ismember(pId, intervals)
            idx = find(intervals == pId);
            batchResults(idx).nPkt = pId;
            batchResults(idx).avgL5g = mean(all_l5g);
            batchResults(idx).avgLSat = mean(all_lSat);
        end
    end
end