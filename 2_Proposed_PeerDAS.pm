// =========================================================================
// Model 2: PeerDAS (Honest)
// =========================================================================

dtmc

// =========================================================================
// [1] Experiment Constraints & Objectives
// =========================================================================

// --- Experiment Variables ------------------------------------------------
const int TOTAL_BLOBS;                      // Total Blobs after expansion
const int CUSTODY_REQUIREMENT = 4;          // Target Subnets (Custody Requirement)
const int UNIQUE_SOURCES_NEEDED = CUSTODY_REQUIREMENT; // Target unique sources (Sybil resistance metric)
const int MAX_NETWORK_LOAD = 5;             // Network congestion level cap
const int START_LOAD = 2;                   // [Experiment Variable] Initial network load
const int MAX_FAIL_TOLERANCE = 4;           // Max consecutive failure tolerance
const int MAX_WINDOW = 3;                   // Max concurrent sampling window
const int HIGH_USAGE_THRES = 2;             // High load threshold

// -------------------------------------------------------------------------
// [Formula] Status Determination & Auxiliary Logic
// -------------------------------------------------------------------------
formula is_success = (stage = 2);                                   // System success state
formula is_running = !is_success;                                   // System running state
formula is_high_usage = (network_load >= HIGH_USAGE_THRES);         // Whether currently under high load
formula is_overloaded = (network_load >= 4);                        // Whether severely overloaded
formula need_switch = (fail_count >= MAX_FAIL_TOLERANCE);           // Whether to trigger circuit breaker
formula is_data_saturated = (k_samples >= CUSTODY_REQUIREMENT);     // Whether data is saturated

// -------------------------------------------------------------------------
// [Formula] Traffic Pressure & Congestion Dynamics
// -------------------------------------------------------------------------
// Traffic Pressure: Full window + Retry = Max pressure
formula traffic_pressure = ((window_size / 3.0) * 0.8) + ((retry_count > 0 ? 1.0 : 0.0) * 0.2);

// Endogenous Deterioration Probability: Coeff 0.12 (Signaling pressure)
formula p_endo_spike = (network_load >= MAX_NETWORK_LOAD) ? 0.0 : 
                       min(0.90, 0.05 + (0.12 * traffic_pressure));

// Endogenous Recovery Probability: Physical baseline 0.6, Resistance coeff 0.10
formula background_recovery_capacity = 1.0 - (network_load / 6.0); 
formula raw_endo_ease = (0.6 * background_recovery_capacity) - (0.10 * traffic_pressure);
formula p_endo_ease = (network_load = 0) ? 0.0 : 
                      min(max(0.05, raw_endo_ease), max(0.0, 1.0 - p_endo_spike));
formula p_endo_stay = max(0.0, 1.0 - p_endo_spike - p_endo_ease);

// =========================================================================
// [2] Time & Latency Parameters (Unit: RTTs)
// =========================================================================
const int SLOT_PENALTY           = 40;      // Attestation Deadline (8.0s)
const int SLOT_DEADLINE          = 20;      // Slot voting deadline
const int SLOT_TICKS             = 60;      // 1 Slot duration
const int GOSSIP_PROP_TICKS      = 1;       // Initial propagation physical wait
const int COST_SAMPLE_RTT        = 1;       // Single sampling request cost (0.2s)
const int COST_FETCH_HEADER      = 2;       // Block header fetch cost
const int COST_DHT_REPAIR        = 5;       // Remote DHT repair cost (5 RTT = 1.0s)
const int COST_SUBNET_RPC        = 2;       // Subnet RPC request cost
const int COST_RETRY_DELAY       = 2;       // Retry cooldown
const int MAX_TOTAL_RETRIES      = 1;       // Maximum retries
const int BACKOFF_BASE           = 1;       // Backoff base
const double BACKOFF_EXP_BASE    = 1.2;     // Exponential backoff base
const double CONGESTION_DELAY_COEFF = 0.3;  // Soft delay coefficient caused by congestion

// =========================================================================
// [3] Physics & Topology Formulas
// =========================================================================
const double PACKET_LOSS_RATE = 0.01;       // Base physical link packet loss rate
const double BASE_SUCCESS = 1 - PACKET_LOSS_RATE; 
const double EXT_LOSS_PENALTY = 0.2;        // External high load penalty
const double MIN_TX_SUCCESS  = 0.05;        // Minimum transmission success rate
const double MIN_DISCOVERY_PROB = 0.05;     // Minimum discovery probability
const double CONGESTION_PENALTY_FACTOR = 0.02; // Congestion penalty factor
const double TOTAL_SUBNETS = 128.0;         // EIP-7594 Total Subnets
const int PEER_DEGREE = 50;                 // Peer degree
const double GOSSIP_PROPAGATION = 0.90;     // Propagation delay coverage loss
const double MIN_ROUTING_VALIDITY  = 0.5;   // Minimum routing validity
const double BASE_CHURN_RATE = 0.01;        // Base network churn rate
const double STALE_VIEW_PENALTY = 0.15;     // Stale view penalty

// [Formula] Structural integrity factor (L3=0.9, L4=0.5)
formula p_blob_integrity = (network_load <= 2) ? 1.0 : 
                          ((network_load = 3) ? 0.90 : 
                          ((network_load = 4) ? 0.50 : 0.10));

// [Formula] Routing validity probability
formula p_routing_validity = (network_load >= 4) ? 0.20 : max(MIN_ROUTING_VALIDITY, 1.0 - BASE_CHURN_RATE - (network_load * STALE_VIEW_PENALTY));

// [Formula] Dynamic subnet RPC probability (L4=0.40)
formula p_subnet_rpc_dynamic = ((network_load <= 2) ? 0.98 : 
                               ((network_load = 3) ? 0.80 : 
                               ((network_load = 4) ? 0.40 : 0.01)));

// [Formula] Block propagation probability (Unified with Model 1)
formula p_block_prop_success = (network_load <= 2) ? 1.0 :
                               ((network_load = 3) ? 0.95 :
                               ((network_load = 4) ? 0.70 : 0.30));

// [Formula] Repair success rate (Pure network repair probability)
formula p_repair_network_only = ((network_load <= 2) ? 0.95 : 
                                ((network_load = 3) ? 0.50 : 0.05));
formula P_REPAIR_OUTCOME = p_repair_network_only;

// [Formula] Topology and discovery probability
formula p_single_peer_hit = CUSTODY_REQUIREMENT / TOTAL_SUBNETS;
formula p_peer_set_coverage = 1.0 - pow(1.0 - p_single_peer_hit, PEER_DEGREE);
formula base_old_peer_prob = p_peer_set_coverage * GOSSIP_PROPAGATION;
formula dynamic_old_peer_prob = base_old_peer_prob * p_routing_validity;

formula base_ratio = (PEER_DEGREE - unique_sources) / (PEER_DEGREE * 1.0);
formula dht_udp_loss = network_load * 0.05; 
formula raw_find_ratio = max(MIN_DISCOVERY_PROB, base_ratio * (1.0 - dht_udp_loss));
formula raw_prob_new = max(MIN_DISCOVERY_PROB, raw_find_ratio);
formula prob_find_new = raw_prob_new;
formula p_same = 1.0 - prob_find_new;

// [Formula] Comprehensive physical transmission success rate calculation
formula cliff_factor = (network_load <= 1) ? 0.971 : ((network_load = 2) ? 0.818 : ((network_load = 3) ? 0.622 : ((network_load = 4) ? 0.378 : 0.182)));
formula internal_penalty = pow(network_load, 2) * CONGESTION_PENALTY_FACTOR;
formula external_penalty = (net_state=1) ? EXT_LOSS_PENALTY : 0.0;
formula self_load_penalty = (window_size * 0.01);
formula upload_saturation_penalty = (CUSTODY_REQUIREMENT / TOTAL_SUBNETS) * network_load * 0.02;
formula frag_penalty = (window_size > 1) ? ((window_size - 1) * 0.02) : 0.0;
formula p_tx_success = max(MIN_TX_SUCCESS, BASE_SUCCESS - internal_penalty - external_penalty - self_load_penalty - frag_penalty - upload_saturation_penalty) * cliff_factor;
formula p_physical_fail = 1.0 - p_tx_success;
formula p_custody_success = p_tx_success;

// [Formula] Effective sampling and spinning
formula p_acquisition_prob = p_tx_success * prob_find_new;
formula p_valid_sample = p_tx_success * p_blob_integrity;
formula p_spin = max(0.0, p_tx_success - p_valid_sample);

// [Formula] Sampling combination probability (Window 1-3)
// Window 1
formula prob_s1_1 = prob_find_new;
formula prob_s1_0 = p_same;
// Window 2
formula prob_s2_2 = pow(prob_find_new, 2);
formula prob_s2_1 = 2 * prob_find_new * p_same;
formula prob_s2_0 = pow(p_same, 2);
// Window 3
formula prob_s3_3 = pow(prob_find_new, 3);
formula prob_s3_2 = 3 * pow(prob_find_new, 2) * p_same;
formula prob_s3_1 = 3 * prob_find_new * pow(p_same, 2);
formula prob_s3_0 = pow(p_same, 3);

// =========================================================================
// [4] Resource & Cost Parameters
// =========================================================================
const double BLOB_SIZE_KB          = 128.0;   // Single Blob size
const int EC_REDUNDANCY            = 2;       // Erasure coding redundancy factor
const double PEERDAS_GOSSIP_BASE   = 5.0;     // PeerDAS base Gossip overhead
const double HEADER_OVERHEAD_RATIO = 0.05;    // Header overhead ratio
const double DHT_QUERY_KB          = 2.0;     // DHT query bandwidth overhead
const double COEFF_PEERDAS         = 0.192;   // PeerDAS latency calculation coefficient
const double RPC_OVERHEAD          = 1.15;    // RPC handshake and header overhead (15%)
formula overhead_inflation = 1.0 ;

// [Formula] Waste multiplier for high load
formula waste_multiplier = (network_load <= 3) ? 1.0 : 
                          ((network_load = 4) ? 1.3 : 2.5);

// [Formula] Dynamic resource calculation
const double BASE_SAMPLE_COST = 1.0;
const double SCALE_OVERHEAD_PER_BLOB = 0.05;
formula COMPUTE_WEIGHT_SAMPLE = BASE_SAMPLE_COST + (TOTAL_BLOBS * SCALE_OVERHEAD_PER_BLOB);
formula scale_penalty = 1.0 + (window_size * 0.05) + (network_load * 0.02);
formula COL_SIZE_KB = (TOTAL_BLOBS * BLOB_SIZE_KB * EC_REDUNDANCY) / TOTAL_SUBNETS; 
formula upload_amp_factor = (network_load >= 4) ? 8.0 : ((network_load = 3) ? 4.0 : 2.0);
formula backoff_slots = BACKOFF_BASE + floor(pow(BACKOFF_EXP_BASE, fail_count));
formula congestion_factor_new = 1.0 + (network_load * 0.1);

// [Modified] Final latency formula
// Logic: Base workload(TOTAL_BLOBS) * Congestion factor * Addressing inflation
formula latency_cost_new = (TOTAL_BLOBS * COEFF_PEERDAS) * congestion_factor_new ;

// =========================================================================
// [5] System Module (PeerDAS Logic)
// =========================================================================
module System

    // 0:Wait, 1:Sample, 2:Verified, 3:Remote_Repair
    stage : [0..3] init 0;
    step : [0..1] init 0;                           // 0: Protocol Action, 1: Env Update
    
    // 0: Init, 1: Ready to Check
    gossip_waited : [0..1] init 0;
    custody_status : [0..1] init 0;
    window_size : [1..MAX_WINDOW] init 3;           // Current concurrent window
    network_load : [0..MAX_NETWORK_LOAD] init START_LOAD;
    
    // Upper bound is strictly CUSTODY_REQUIREMENT
    k_samples : [0..CUSTODY_REQUIREMENT] init 0;
    
    unique_sources : [0..UNIQUE_SOURCES_NEEDED] init 0;
    fail_count : [0..MAX_FAIL_TOLERANCE] init 0;    // Consecutive failure counter
    net_state : [0..1] init 0;                      // 0: Normal, 1: Congested
    backoff_timer : [0..40] init 0;                 // Backoff timer
    retry_count : [0..MAX_TOTAL_RETRIES] init 0;    // Retry counter

    // =========================================================================
    // [Stage 0: Initialization & Gossip Wait]
    // =========================================================================
    
    // [Step A: Start Wait] 
    // Consume physical time immediately upon init
    [] (is_running) & (stage=0) & (step=0) & (backoff_timer=0) & (gossip_waited=0) -> 
        1.0 : 
            (backoff_timer' = GOSSIP_PROP_TICKS) & // Set wait time (1 RTT)
            (gossip_waited' = 1) &               
            (step' = 1);

    // [Step B: Gossip Resolution]
    [] (is_running) & (stage=0) & (step=0) & (backoff_timer=0) & (gossip_waited=1) -> 
        
        // Branch 1: Header propagation success
        p_block_prop_success : 
            (stage' = 1) & 
            (custody_status' = 0) & 
            (step' = 1) +
            
        // Branch 2: Header lost (Severe failure)
        (1.0 - p_block_prop_success) : 
            (stage' = 1) & 
            (custody_status' = 0) & 
            (backoff_timer' = COST_FETCH_HEADER) & 
            (step' = 1);

    // =========================================================================
    // [Action 1: Finalization & Repair Logic] 
    // =========================================================================
    
    // [Action 1a: Try Finalize]
    // Trigger: Samples met (k>=K) AND Sources met
    // Logic: As long as sampling succeeds, enter Stage 2 (Consensus Voting).
    // Custody data missing does not block success state but sets custody_status=0.
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (need_switch) & 
       (k_samples >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED) -> 
            
            // Branch A: Perfect Success (Consensus + Custody Data)
            p_custody_success : 
                (stage' = 2) & 
                (custody_status' = 1) & 
                (fail_count' = 0) & 
                (step' = 1) +

            // Branch B: Consensus Success but Custody Missing
            (1.0 - p_custody_success) : 
                (stage' = 2) & 
                (custody_status' = 0) & 
                (fail_count' = 0) &
                (step' = 1);

    // [Action 1b: Explicit Fail]
    // Trigger: Sampling itself insufficient (k < K), must repair regardless of custody
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (need_switch) & 
       (
         (k_samples < CUSTODY_REQUIREMENT) | 
         (unique_sources < UNIQUE_SOURCES_NEEDED)
       ) -> 
            1.0 : (stage' = 3) & 
                  (backoff_timer' = COST_DHT_REPAIR) & 
                  (step' = 1);

    // [Action 1c: Timer Tick]
    [] (is_running) & (stage>=0) & (step=0) & (backoff_timer > 0) -> 
        1.0 : (backoff_timer' = backoff_timer - 1) & (step'=1);

    // [Action 1d: Repair Outcome]
    [] (is_running) & (stage=3) & (step=0) & (backoff_timer=0) ->
        
        // --- Branch A: Repair Success ---
        P_REPAIR_OUTCOME : 
            (stage' = 2) & 
            (k_samples' = max(k_samples,CUSTODY_REQUIREMENT)) &
            (unique_sources' = max(unique_sources, UNIQUE_SOURCES_NEEDED)) &
            (custody_status' = 1) & 
            (fail_count' = 0) & 
            (step' = 1) +

        // --- Branch B: Fail but Retry (Model 2: Always retain data) ---
        ((1.0 - P_REPAIR_OUTCOME) * ((retry_count < MAX_TOTAL_RETRIES) ? 1.0 : 0.0)) : 
            (stage' = 1) &                
            (retry_count' = retry_count + 1) & 
            (fail_count' = 0) & 
            (backoff_timer' = COST_RETRY_DELAY) & 
            
            // Retain progress (Pending Samples mechanism)
            (k_samples' = k_samples) & 
            (unique_sources' = unique_sources) &
            (window_size' = 1) & 
            
            (step' = 1) +

        // --- Branch C: Hard Reset ---
        ((1.0 - P_REPAIR_OUTCOME) * ((retry_count >= MAX_TOTAL_RETRIES) ? 1.0 : 0.0)) : 
            (stage' = 0) & 
            (fail_count' = 0) & 
            (retry_count' = 0) &          
            (k_samples' = 0) &            
            (unique_sources' = 0) &       
            (window_size' = MAX_WINDOW) & 

            // Reset wait flag
            (gossip_waited' = 0) & 

            (backoff_timer' = SLOT_PENALTY) & 
            (step' = 1);

    // =========================================================================
    // [Action 2: Window = 1 (Serial Mode)]
    // =========================================================================
   [] (is_running) & (stage=1) & (step=0) & (backoff_timer=0) & (!need_switch) & (window_size = 1) ->
        // --- 1. Valid Success ---
        // 1.1 New Peer Success
        (p_valid_sample * prob_s1_1) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & 
            (fail_count' = 0) & 
            (window_size' = min(MAX_WINDOW, window_size + 1)) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT) & 
            (step' = 1) +
        
        // 1.2 Old Peer Success
        (p_valid_sample * prob_s1_0 * dynamic_old_peer_prob) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & 
            (unique_sources' = unique_sources) & 
            (fail_count' = 0) & 
            (window_size' = min(MAX_WINDOW, window_size + 1)) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT) & 
            (step' = 1) +
        
        // 1.3 Old Peer Empty (Miss)
        (p_valid_sample * prob_s1_0 * (1.0 - dynamic_old_peer_prob)) : 
            (k_samples' = k_samples) & 
            (unique_sources' = unique_sources) & 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (window_size' = window_size) & 
            (stage' = stage) & 
            (backoff_timer' = COST_SAMPLE_RTT) & 
            (step' = 1) +
        
        // --- 2. Physical Fail -> Subnet RPC Repair ---
        // Branch A: RPC Success
        ((1.0 - p_tx_success) * p_subnet_rpc_dynamic) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & 
            (fail_count' = 0) & 
            (window_size' = window_size) & 
            (backoff_timer' = COST_SUBNET_RPC) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

        // Branch B: RPC Fail -> DHT Repair
        ((1.0 - p_tx_success) * (1.0 -p_subnet_rpc_dynamic)) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & 
            (window_size' = max(1, floor(window_size / 2))) & 
            (backoff_timer' = COST_DHT_REPAIR) &  
            (stage' = 1) & (step' = 1) +

        // --- 3. Spin ---
        (p_spin) : (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1);

    // =========================================================================
    // [Action 3: Window = 2] (With Spinning Mechanics)
    // =========================================================================
    
    [] (is_running) & (stage=1) & (step=0) & (backoff_timer=0) & (!need_switch) & (window_size = 2) ->
        
        // --- CASE A: All Valid Success ---
        // A.1: 2 New
        (pow(p_valid_sample, 2) * prob_s2_2) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 2)) & (fail_count' = 0) & (window_size' = min(MAX_WINDOW, window_size + 1)) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 2) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.2: 1 New + 1 Old (Hit)
        (pow(p_valid_sample, 2) * prob_s2_1 * dynamic_old_peer_prob) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (fail_count' = 0) & (window_size' = min(MAX_WINDOW, window_size + 1)) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.3: 1 New + 1 Old (Miss)
        (pow(p_valid_sample, 2) * prob_s2_1 * (1.0 - dynamic_old_peer_prob)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (fail_count' = 0) & (window_size' = min(MAX_WINDOW, window_size + 1)) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.4: 2 Old (Hit/Hit)
        (pow(p_valid_sample, 2) * prob_s2_0 * pow(dynamic_old_peer_prob, 2)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = unique_sources) & (fail_count' = 0) & (window_size' = min(MAX_WINDOW, window_size + 1)) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.5: 2 Old (Hit/Miss)
        (pow(p_valid_sample, 2) * prob_s2_0 * 2 * dynamic_old_peer_prob * (1.0-dynamic_old_peer_prob)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (fail_count' = 0) & (window_size' = min(MAX_WINDOW, window_size + 1)) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.6: 2 Old (Miss/Miss)
        (pow(p_valid_sample, 2) * prob_s2_0 * pow(1.0-dynamic_old_peer_prob, 2)) : (k_samples' = k_samples) & (unique_sources' = unique_sources) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & (window_size' = window_size) & (stage' = stage) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // --- CASE B: Partial Physical Loss (1 Success 1 Fail) ---
        // B.1: 1 New
        (2 * p_tx_success * (1-p_tx_success) * prob_s1_1) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (fail_count' = 0) & (window_size' = max(1, floor(window_size / 2))) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // B.2: 1 Old (Hit)
        (2 * p_tx_success * (1-p_tx_success) * prob_s1_0 * dynamic_old_peer_prob) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = unique_sources) & (fail_count' = 0) & (window_size' = max(1, floor(window_size / 2))) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // B.3: 1 Old (Miss)
        (2 * p_tx_success * (1-p_tx_success) * prob_s1_0 * (1.0 - dynamic_old_peer_prob)) : (k_samples' = k_samples) & (unique_sources' = unique_sources) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & (window_size' = max(1, floor(window_size / 2))) & (stage' = stage) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
       // --- CASE C: Physical Fail -> Subnet RPC Repair ---
        // Branch A: RPC Success
        ((1.0 - (pow(p_tx_success, 2) + 2 * p_tx_success * (1-p_tx_success))) * p_subnet_rpc_dynamic) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & 
            (fail_count' = 0) & 
            (window_size' = max(1, floor(window_size / 2))) & 
            (backoff_timer' = COST_SUBNET_RPC) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

        // Branch B: RPC Fail
        ((1.0 - (pow(p_tx_success, 2) + 2 * p_tx_success * (1-p_tx_success))) * (1.0 - p_subnet_rpc_dynamic)) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & 
            (window_size' = max(1, floor(window_size / 2))) & 
            (backoff_timer' = COST_DHT_REPAIR) &  
            (stage' = 1) & (step' = 1) +

        // --- CASE D: Spin Complement ---
      max(0.0, pow(p_tx_success, 2) - pow(p_valid_sample, 2)) :(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1);

   // =========================================================================
    // [Action 4: Window = 3] (With Spinning Mechanics)
    // =========================================================================
    
    [] (is_running) & (stage=1) & (step=0) & (backoff_timer=0) & (!need_switch) & (window_size = 3) ->
        
        // --- CASE A: All Valid Success ---
        // A.1 [3 New]
        (pow(p_valid_sample, 3) * prob_s3_3) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 3)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 3)) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 3) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.2 [2 New + 1 Old (Hit)]
        (pow(p_valid_sample, 3) * prob_s3_2 * dynamic_old_peer_prob) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 3)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 2)) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 2) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.3 [2 New + 1 Old (Miss)]
        (pow(p_valid_sample, 3) * prob_s3_2 * (1.0-dynamic_old_peer_prob)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 2)) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 2) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.4 [1 New + 2 Old (HH)]
        (pow(p_valid_sample, 3) * prob_s3_1 * pow(dynamic_old_peer_prob, 2)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 3)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >=CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.5 [1 New + 2 Old (HM)]
        (pow(p_valid_sample, 3) * prob_s3_1 * 2 * dynamic_old_peer_prob * (1.0-dynamic_old_peer_prob)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.6 [1 New + 2 Old (MM)]
        (pow(p_valid_sample, 3) * prob_s3_1 * pow(1.0-dynamic_old_peer_prob, 2)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.7 [3 Old (HHH)]
        (pow(p_valid_sample, 3) * prob_s3_0 * pow(dynamic_old_peer_prob, 3)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 3)) & (unique_sources' = unique_sources) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.8 [3 Old (HHM)]
        (pow(p_valid_sample, 3) * prob_s3_0 * 3 * pow(dynamic_old_peer_prob, 2) * (1.0-dynamic_old_peer_prob)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = unique_sources) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.9 [3 Old (HMM)]
        (pow(p_valid_sample, 3) * prob_s3_0 * 3 * dynamic_old_peer_prob * pow(1.0-dynamic_old_peer_prob, 2)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = unique_sources) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >=CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.10 [3 Old (MMM)]
        (pow(p_valid_sample, 3) * prob_s3_0 * pow(1.0-dynamic_old_peer_prob, 3)) : (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = window_size) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & (stage' = stage) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // --- CASE B: Partial Physical Loss (2 Success 1 Fail) ---
        // B.1 [2 New]
        (3 * pow(p_tx_success, 2) * (1-p_tx_success) * prob_s2_2) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 2)) & (fail_count' = 0) & (window_size' = max(1, floor(window_size / 2))) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 2) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // B.2 [1 New + 1 Old (Hit)]
        (3 * pow(p_tx_success, 2) * (1-p_tx_success) * prob_s2_1 * dynamic_old_peer_prob) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (fail_count' = 0) & (window_size' = max(1, floor(window_size / 2))) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // B.3 [1 New + 1 Old (Miss)]
        (3 * pow(p_tx_success, 2) * (1-p_tx_success) * prob_s2_1 * (1.0-dynamic_old_peer_prob)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (fail_count' = 0) & (window_size' = max(1, floor(window_size / 2))) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // B.4 [2 Old (HH)]
        (3 * pow(p_tx_success, 2) * (1-p_tx_success) * prob_s2_0 * pow(dynamic_old_peer_prob, 2)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 2)) & (unique_sources' = unique_sources) & (fail_count' = 0) & (window_size' = max(1, floor(window_size / 2))) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // B.5 [2 Old (HM)]
        (3 * pow(p_tx_success, 2) * (1-p_tx_success) * prob_s2_0 * 2 * dynamic_old_peer_prob * (1.0-dynamic_old_peer_prob)) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = unique_sources) & (fail_count' = 0) & (window_size' = max(1, floor(window_size / 2))) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // B.6 [2 Old (MM)]
        (3 * pow(p_tx_success, 2) * (1-p_tx_success) * prob_s2_0 * pow(1.0-dynamic_old_peer_prob, 2)) : (k_samples' = k_samples) & (unique_sources' = unique_sources) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & (window_size' = max(1, floor(window_size / 2))) & (stage' = stage) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // --- CASE C: Severe Physical Loss (1 Success 2 Fail) ---
        // C.1 [1 New]
        (3 * p_tx_success * pow(1-p_tx_success, 2) * prob_s1_1) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & (window_size' = max(1, floor(window_size / 2))) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // C.2 [1 Old (Hit)]
        (3 * p_tx_success * pow(1-p_tx_success, 2) * prob_s1_0 * dynamic_old_peer_prob) : (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size / 2))) & (fail_count' = 0) & (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
        (backoff_timer' =COST_SAMPLE_RTT) & (step' = 1) +
        
        // C.3 [1 Old (Miss)]
        (3 * p_tx_success * pow(1-p_tx_success, 2) * prob_s1_0 * (1.0 - dynamic_old_peer_prob)) : (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size / 2))) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & (stage' = stage) & 
        (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
       // --- CASE D: Physical Fail -> Subnet RPC Repair ---
        
        // Branch A: RPC Success
        ((1.0 - (pow(p_tx_success, 3) + 3 * pow(p_tx_success, 2) * (1-p_tx_success) + 3 * p_tx_success * pow(1-p_tx_success, 2))) * p_subnet_rpc_dynamic) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples + 1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & 
            (fail_count' = 0) & 
            (window_size' = max(1, floor(window_size / 2))) & 
            (backoff_timer' = COST_SUBNET_RPC) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

        // Branch B: RPC Fail
        ((1.0 - (pow(p_tx_success, 3) + 3 * pow(p_tx_success, 2) * (1-p_tx_success) + 3 * p_tx_success * pow(1-p_tx_success, 2))) * (1.0 - p_subnet_rpc_dynamic)) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) & 
            (window_size' = max(1, floor(window_size / 2))) & 
            (backoff_timer' = COST_DHT_REPAIR) & 
            (stage' = 1) & (step' = 1) +

        // --- CASE E: Spin Complement ---
       max(0.0, pow(p_tx_success, 3) - pow(p_valid_sample, 3)) :(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1);
    
    // =========================================================================
    // [Action 5: Stage 2 Background Repair] 
    // =========================================================================
  
    
    []  (stage=2) & (step=0) & (custody_status=0) ->
        
        // Branch A: Repair Success
        // Use p_repair_network_only or p_tx_success as probability
        p_repair_network_only : 
            (custody_status' = 1) &  
            (fail_count' = 0) & 
            (step' = 0) +
            
        // Branch B: Repair Fail, Keep Waiting
        (1.0 - p_repair_network_only) : 
            (custody_status' = 0) &  
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (step' = 0) ;
  
    // [Step 1: Environment Update] (Endogenous Feedback)
    [] (is_running) & (step=1) ->
        // 1. Congestion Spike
        p_endo_spike : (step'=0) & 
            (network_load' = min(MAX_NETWORK_LOAD, network_load + 1)) & 
            (net_state' = (min(MAX_NETWORK_LOAD, network_load + 1) >= HIGH_USAGE_THRES) ? 1 : net_state) +
            
        // 2. Congestion Ease
        p_endo_ease : (step'=0) & 
            (network_load' = (network_load > 0 ? network_load - 1 : 0)) & 
            (net_state' = ((max(0, network_load - 1) >= HIGH_USAGE_THRES) ? 1 : 0)) +
            
        // 3. Stay
        p_endo_stay : (step'=0) & 
            (network_load' = network_load) & 
            (net_state' = (is_high_usage ? 1 : 0));
    
    // [Sink State]
    [] (!is_running) & (custody_status=1) -> 1.0 : (stage' = stage) & (step' = 0);
    [] (stage=2) & (step=1) -> 1.0 : (step'=0);
endmodule

// -------------------------------------------------------------------------
// [6] Rewards 
// -------------------------------------------------------------------------

rewards "bandwidth_usage"
    // Sampling phase total overhead
    [] (step=0) & (stage=1) & (is_running) & (backoff_timer=0) & (!need_switch) :        
        // 1. Base Signaling (Gossip + DHT Query)
        ((PEERDAS_GOSSIP_BASE * overhead_inflation ) + (fail_count * DHT_QUERY_KB )) * waste_multiplier +        
        // 2. Sample Download
        (window_size * COL_SIZE_KB) * waste_multiplier +       
        // 3. Subnet RPC Rescue Attempt
        ((window_size=1) ? 
            (1.0 - p_tx_success) * COL_SIZE_KB * RPC_OVERHEAD * waste_multiplier : 0) +            
        ((window_size=2) ? 
            (1.0 - (pow(p_tx_success, 2) + 2*p_tx_success*(1-p_tx_success))) * COL_SIZE_KB * RPC_OVERHEAD * waste_multiplier : 0) +           
        ((window_size=3) ? 
            (1.0 - (pow(p_tx_success, 3) + 3*pow(p_tx_success, 2)*(1-p_tx_success) + 3*p_tx_success*pow(1-p_tx_success, 2))) * COL_SIZE_KB * RPC_OVERHEAD * waste_multiplier : 0);
    // Custody Data Download
    [] (stage=0) & (step=0) & (gossip_waited=1) :
        p_block_prop_success * (CUSTODY_REQUIREMENT * COL_SIZE_KB * upload_amp_factor * waste_multiplier);
    //  Remote Repair (Stage 3)
    [] (stage=1) & (step=0) & (backoff_timer=0) & (need_switch | k_samples < CUSTODY_REQUIREMENT | unique_sources < UNIQUE_SOURCES_NEEDED) : 
        (max(0, CUSTODY_REQUIREMENT - k_samples) * COL_SIZE_KB * 1.1  * waste_multiplier);
    // Background Custody Completion
    [] (stage=1) & (step=0) & (backoff_timer=0) & (need_switch) & (k_samples >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED) :
        (1.0 - p_custody_success) * (CUSTODY_REQUIREMENT * COL_SIZE_KB * waste_multiplier);
        // Cyclic billing corresponding to Action 5
    // Trigger: Voted (Stage 2) but missing data (Custody 0)
    // Physical meaning: Each background repair attempt consumes 10% of full data bandwidth (simulating handshake/query/partial transfer overhead)
    // If network is congested, cycle count increases, and total cost accumulates automatically, ensuring high precision.
    [] (stage=2) & (step=0) & (custody_status=0) : 
        (CUSTODY_REQUIREMENT * COL_SIZE_KB * 0.10 * waste_multiplier);
endrewards

rewards "latency_rtts"
    // Hard Latency
    (is_running) & (step=0) & (backoff_timer > 0) : 1;
    
    // Soft Latency
    (is_running) & (step=0) & (backoff_timer > 0) & (network_load > 2) : 
        (network_load - 2) * CONGESTION_DELAY_COEFF;
    
    // Final Latency
   [] (stage=2) & (step=1) : latency_cost_new;
endrewards

rewards "compute_cost"
    //  Sampling & Verification (Stage 1)
    [] (step=0) & (stage=1) & (is_running) & (backoff_timer=0) & (!need_switch) :         
        // 1. Base Sample Verification
        window_size * scale_penalty * (
            (p_valid_sample * COMPUTE_WEIGHT_SAMPLE) + 
            (p_spin * (COMPUTE_WEIGHT_SAMPLE * 0.1))
        ) +
        // 2. Subnet RPC Rescue Verification
        ((window_size=1) ? 
            (1.0 - p_tx_success) * p_subnet_rpc_dynamic * COMPUTE_WEIGHT_SAMPLE : 0
        ) +
        ((window_size=2) ? 
            (1.0 - (pow(p_tx_success, 2) + 2*p_tx_success*(1-p_tx_success))) * p_subnet_rpc_dynamic * COMPUTE_WEIGHT_SAMPLE : 0
        ) +
        ((window_size=3) ? 
            (1.0 - (pow(p_tx_success, 3) + 3*pow(p_tx_success, 2)*(1-p_tx_success) + 3*p_tx_success*pow(1-p_tx_success, 2))) * p_subnet_rpc_dynamic * COMPUTE_WEIGHT_SAMPLE : 0
        );       
    // Remote Repair Verification (Remote Repair - Stage 3)
    [] (stage=3) & (step=0) & (backoff_timer=0) : 
        (max(0, CUSTODY_REQUIREMENT - k_samples) * COMPUTE_WEIGHT_SAMPLE);

endrewards

// Success Label: Used for logic formula checking (Pctl)
label "success" = (stage=2) & (step=0);
// Attestation with Debt
label "attestation_with_debt" = (stage=2) & (custody_status=0);
//DoS Give-up
label "dos_giveup" = (stage=0) & (retry_count=0) & (backoff_timer=SLOT_PENALTY) & (step=1);