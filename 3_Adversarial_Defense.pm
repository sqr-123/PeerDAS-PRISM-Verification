// =========================================================================
// Model 3: PeerDAS Safety Verification (Safety & Defense Model)
// =========================================================================

dtmc

// =========================================================================
// [1] Experiment Constraints & Objectives
// =========================================================================

// --- Experiment Variables ------------------------------------------------
const int TOTAL_BLOBS = 6;                  // Total Blobs
const int CUSTODY_REQUIREMENT =4;          // Custody requirement (K value)
const int UNIQUE_SOURCES_NEEDED = CUSTODY_REQUIREMENT; // Target unique sources
const int MAX_NETWORK_LOAD = 5;             // Network load cap
const int START_LOAD = 2;                   // Initial network load
const int MAX_FAIL_TOLERANCE = 4;           // Failure tolerance limit
const int MAX_WINDOW = 3;                   // Max window size
const int HIGH_USAGE_THRES = 2;             // High load threshold

// -------------------------------------------------------------------------
// [Formula] Status Determination & Auxiliary Logic
// -------------------------------------------------------------------------
formula is_success = (stage = 2);                                   // System success state
formula is_running = !is_success;                                   // System running state
formula is_high_usage = (network_load >= HIGH_USAGE_THRES);         // High load determination
formula is_congested_env  = (network_load >= 3);                    // Congested environment determination
formula need_switch = (fail_count >= MAX_FAIL_TOLERANCE);           // Circuit breaker trigger condition
formula is_eclipsed = (subnet_state = 0);                           // Eclipsed state flag
formula is_data_saturated = (k_samples >= CUSTODY_REQUIREMENT);     // Data saturation check

// -------------------------------------------------------------------------
// [Formula] Traffic Pressure & Congestion Dynamics (Endogenous Feedback)
// -------------------------------------------------------------------------
formula traffic_pressure = ((window_size / 3.0) * 0.8) + ((retry_count > 0 ? 1.0 : 0.0) * 0.2);

formula p_matrix_spike = (network_load >= MAX_NETWORK_LOAD) ? 0.0 : 
                         min(0.90, 0.05 + (0.12 * traffic_pressure));

formula background_recovery_capacity = 1.0 - (network_load / 6.0); 
formula raw_endo_ease = (0.6 * background_recovery_capacity) - (0.10 * traffic_pressure);

formula p_matrix_ease = (network_load = 0) ? 0.0 : 
                        min(max(0.05, raw_endo_ease), max(0.0, 1.0 - p_matrix_spike));

formula p_matrix_stay = 1.0 - p_matrix_spike - p_matrix_ease;

// =========================================================================
// [2] Attack Model Parameters (Eclipse & Sybil)
// =========================================================================
const double p_malicious_init =0.1;          // Initial malicious ratio
const double P_ECLIPSED_DENSITY = 0.9;      // Malicious density after Eclipse
const double ATTACK_SILENT =0.5;           // Silent attack probability
const double RATE_SELECTIVE_DISCLOSURE =0.1; // Selective disclosure probability
const double ADVERSARIAL_FILTERING_COEFF = 1; // Adversary filtering coeff (libp2p/GossipSub)
const double ECLIPSE_LEAK_FACTOR = 0.1;     // Data leak factor under Eclipse
const double MIN_ATTACK_CPU_LOAD = 0.5;     // Min CPU load for attack traffic

// [Formula] Attack Strategies & Probabilities
// Logic Update: Removed explicit check for p_malicious_init > 0 to eliminate God View.
// The probability is now purely derived from the calculated current state.
formula p_curr_mal = (subnet_state=1) ? (p_malicious_init * ADVERSARIAL_FILTERING_COEFF) : P_ECLIPSED_DENSITY;
formula p_mal = p_curr_mal;
formula p_hon = 1.0 - p_mal;

formula strategy_p_silent = ATTACK_SILENT;
formula strategy_p_disclosure = (subnet_state=0) ? RATE_SELECTIVE_DISCLOSURE : 0.0;
formula strategy_p_griefing = max(0.0, 1.0 - strategy_p_silent - strategy_p_disclosure);

formula p_interaction_fails = p_tx_success * strategy_p_griefing; 
formula p_disclosure_succeeds = p_tx_success * strategy_p_disclosure;   
formula p_bad_silent = 1.0 - p_interaction_fails - p_disclosure_succeeds; 
formula p_bad_is_active = p_interaction_fails + p_disclosure_succeeds; 

// =========================================================================
// [3] Defense & Suspicion Mechanism
// =========================================================================
const int MAX_SUSPICION = 5;                // Max suspicion score cap
const int PENALTY_GRIEFING =5 ;             // Penalty for griefing
const int PENALTY_SILENT = 2;               // Penalty for silence
const int DECAY_RATE = 1;                   // Suspicion decay rate
const int PENALTY_MINOR = 1;                // Minor penalty
const double P_DECAY = 0.25;                // Natural suspicion decay probability
const double P_INTRUSION_HIGH_RISK = 0.15;
const double P_INTRUSION_MED_RISK = 0.05;
const double P_INTRUSION_LOW_RISK = 0.02;
const double P_INTRUSION_BASE_NOISE = 0.001;

// [Formula] Intrusion & Escape Probabilities
// Logic Update: Removed explicit check for p_malicious_init > 0.
// Intrusion suspicion is now based solely on subnet state, load, and history.
// P_INTRUSION_BASE_NOISE ensures even honest networks have a non-zero (but low) suspicion rate due to noise.
formula p_intrusion_prob = (subnet_state=1) ? 
    ((network_load >= 3) ? 
        ((suspicion_count >= 2) ? P_INTRUSION_HIGH_RISK : P_INTRUSION_MED_RISK) : 
        ((suspicion_count >= 2) ? P_INTRUSION_LOW_RISK : max(0.005, P_INTRUSION_BASE_NOISE))) : 0.0;

formula p_escape_success = (subnet_state = 2) ? max(0.01, 1.0 - p_malicious_init) : 1.0;
formula p_int = p_intrusion_prob;
formula p_safe = 1.0 - p_intrusion_prob;

// =========================================================================
// [4] Time & Re-peering Parameters
// =========================================================================
const int GOSSIP_PROP_TICKS = 1;            // Initial propagation physical wait
const int SLOT_PENALTY = 40;                // Slot penalty (40 RTTs)
const int SLOT_DEADLINE = 20;               // Voting deadline
const int SLOT_MAX = 180;  
const int REPEER_DELAY = 20;                // Re-peering penalty delay
const int SLOT_TICKS = 60;                  // 1 Slot duration
const int TIMEOUT_DELAY = 5;                // Silence timeout threshold
const int COST_SAMPLE_RTT = 1;              // Sampling cost
const int COST_DHT_REPAIR = 5;              // DHT repair cost
const int COST_SUBNET_RPC = 2;              // Subnet RPC cost
const int COST_FETCH_HEADER = 2;            // Header fetch cost
const int COST_RETRY_DELAY = 2;             // Retry cooldown
const int MAX_TOTAL_RETRIES = 1;            // Max retries
const int BACKOFF_BASE = 1;                 // Backoff base
const double BACKOFF_EXP_BASE = 1.2;        // Backoff exponent
const double CONGESTION_DELAY_COEFF = 0.3;  // Congestion soft delay coefficient

// =========================================================================
// [5] Physics & Topology Parameters
// =========================================================================
const double PACKET_LOSS_RATE = 0.01;       // Physical packet loss rate
const double BASE_SUCCESS = 1 - PACKET_LOSS_RATE;
const double EXT_LOSS_PENALTY = 0.2;        // External penalty
const double MIN_TX_SUCCESS = 0.05;         // Min transmission rate
const double MIN_DISCOVERY_PROB = 0.05;     // Min discovery rate
const double CONGESTION_PENALTY_FACTOR = 0.02; // Congestion penalty
const double TOTAL_SUBNETS = 128.0;         // Total subnets
const int PEER_DEGREE = 50;                 // Peer degree
const double GOSSIP_PROPAGATION = 0.90;     // Propagation coverage
const double MIN_ROUTING_VALIDITY = 0.5;    // Min routing validity
const double BASE_CHURN_RATE = 0.01;        // Base churn rate
const double STALE_VIEW_PENALTY = 0.15;     // Stale view penalty

// [Formula] Discovery & Topology Calculations
formula dht_udp_loss = network_load * 0.05;
formula base_ratio = (PEER_DEGREE - unique_sources) / (PEER_DEGREE * 1.0);
formula raw_find_ratio = max(MIN_DISCOVERY_PROB, base_ratio * (1.0 - dht_udp_loss));
formula routing_pollution = pow(p_mal, 1.5);
formula effective_min_discovery = (is_eclipsed & subnet_state != 2) ? (MIN_DISCOVERY_PROB * ECLIPSE_LEAK_FACTOR) : MIN_DISCOVERY_PROB;
formula raw_prob_new = is_eclipsed ? effective_min_discovery : (max(effective_min_discovery, raw_find_ratio) * (1.0 - routing_pollution));
formula prob_find_new = raw_prob_new;
formula p_same = 1.0 - prob_find_new;
formula p_eff_new = 1.0; 

// [Formula] Topology Base Probabilities
formula K_VAL = CUSTODY_REQUIREMENT + 0.0;
formula p_single_peer_hit = K_VAL / TOTAL_SUBNETS;

formula p_peer_set_coverage = 1.0 - pow(1.0 - p_single_peer_hit, PEER_DEGREE);
formula base_old_peer_prob = p_peer_set_coverage * GOSSIP_PROPAGATION;
formula p_routing_validity = (network_load >= 4) ? 0.20 : max(MIN_ROUTING_VALIDITY, 1.0 - BASE_CHURN_RATE - (network_load * STALE_VIEW_PENALTY));
formula dynamic_old_peer_prob_honest = base_old_peer_prob * p_routing_validity;
formula p_eff_old = (subnet_state = 0) ? (dynamic_old_peer_prob_honest * ECLIPSE_LEAK_FACTOR) : dynamic_old_peer_prob_honest;

// [Formula] Block Propagation Probability
formula p_block_prop_success = (network_load <= 2) ? 1.0 :
                               ((network_load = 3) ? 0.95 :
                               ((network_load = 4) ? 0.70 : 0.30));

// [Formula] Physical Repair Probability
formula p_dht_lookup_success = (network_load <= 2) ? 0.95 : 
                               ((network_load = 3) ? 0.50 : 0.05);
formula P_REPAIR_OUTCOME = (subnet_state = 0) ? 0.0 : p_dht_lookup_success;

// [Formula] Physical Integrity & RPC
formula p_blob_integrity = (network_load <= 2) ? 1.0 : 
                          ((network_load = 3) ? 0.90 : 
                          ((network_load = 4) ? 0.50 : 0.10));
formula p_rpc_phys_raw = (network_load <= 2) ? 0.98 : 
                         ((network_load = 3) ? 0.80 : 
                         ((network_load = 4) ? 0.40 : 0.05));
formula P_RPC_EFFECTIVE = (subnet_state = 0) ? 0.0 : p_rpc_phys_raw;

// [Formula] Physical Transmission Comprehensive
formula cliff_factor = (network_load <= 1) ? 0.971 : ((network_load = 2) ? 0.818 : ((network_load = 3) ? 0.622 : ((network_load = 4) ? 0.378 : 0.182)));
formula internal_penalty = pow(network_load, 2) * CONGESTION_PENALTY_FACTOR; 
formula external_penalty = (net_state=1) ? EXT_LOSS_PENALTY : 0.0;
formula self_load_penalty = (window_size * 0.01);
formula frag_penalty = (window_size > 1) ? ((window_size - 1) * 0.02) : 0.0;
formula upload_saturation_penalty = (K_VAL / TOTAL_SUBNETS) * network_load * 0.02;

formula p_tx_success = max(MIN_TX_SUCCESS, BASE_SUCCESS - internal_penalty - external_penalty - self_load_penalty - frag_penalty - upload_saturation_penalty) * cliff_factor;
formula p_phys_tx = p_tx_success;
formula p_log_valid = p_phys_tx * p_blob_integrity;
formula p_hon_spin = max(0.0, p_phys_tx - p_log_valid);
formula p_outcome_valid_cond = p_tx_success;
formula p_outcome_waste_good = 1.0 - p_tx_success;
formula p_custody_success_safe = (subnet_state = 0) ? (p_tx_success * 0.1) : p_tx_success;

// [Formula] Combinatorial Probabilities (Windows 2 & 3)
// Attack Branch
formula p_w2_all_mal = pow(p_mal, 2);
formula p_w2_mixed   = 2 * p_mal * p_hon;
formula p_w2_all_hon = pow(p_hon, 2);
formula p_w3_all_mal = pow(p_mal, 3);
formula p_w3_mixed_bad  = 3 * pow(p_mal, 2) * p_hon; 
formula p_w3_mixed_good = 3 * p_mal * pow(p_hon, 2); 
formula p_w3_all_hon = pow(p_hon, 3);

// Mixed Combinations
formula p_w2_mix_slow = p_w2_mixed * p_bad_silent; 
formula p_w2_mix_disc = p_w2_mixed * p_disclosure_succeeds; 
formula p_w2_mix_fail = p_w2_mixed * p_interaction_fails; 
formula p_w3_2b_2disc = p_w3_mixed_bad * pow(p_disclosure_succeeds, 2);
formula p_w3_2b_1disc = p_w3_mixed_bad * (2 * p_disclosure_succeeds * p_interaction_fails);
formula p_w3_2b_0disc = p_w3_mixed_bad * pow(p_interaction_fails, 2);
formula p_w3_2b1g_slow = p_w3_mixed_bad * (1.0 - pow(p_bad_is_active, 2)); 
formula p_w3_1b_1disc = p_w3_mixed_good * p_disclosure_succeeds;
formula p_w3_1b_0disc = p_w3_mixed_good * p_interaction_fails;
formula p_w3_1b2g_slow = p_w3_mixed_good * p_bad_silent;

// Window 2 Honest Branch
formula prob_s2_2 = pow(prob_find_new, 2);               
formula prob_s2_1 = 2 * prob_find_new * p_same;         
formula prob_s2_0 = pow(p_same, 2);     

// Window 3 Honest Branch
formula prob_s3_3 = pow(prob_find_new, 3);               
formula prob_s3_2 = 3 * pow(prob_find_new, 2) * p_same; 
formula prob_s3_1 = 3 * prob_find_new * pow(p_same, 2); 
formula prob_s3_0 = pow(p_same, 3); 

// =========================================================================
// [6] Resource & Cost Parameters
// =========================================================================
const double BLOB_SIZE_KB = 128.0;          // Blob size
const int EC_REDUNDANCY = 2;                // EC redundancy (Physical calc)
const double PEERDAS_GOSSIP_BASE = 5.0;     // Base Gossip overhead
const double HEADER_OVERHEAD_RATIO = 0.05;  // Header overhead ratio
const double DHT_QUERY_KB = 2.0;            // DHT query overhead
const double REPEER_METADATA_KB = 2.0;      // Re-peering metadata overhead
const double REPEER_COST_FACTOR = 3.0;      // Re-peering cost factor
const double COEFF_PEERDAS = 0.192;         // Latency coeff
const double RPC_OVERHEAD = 1.15;            // RPC overhead

// [Formula] Dynamic Resource Calculation
const double BASE_SAMPLE_COST = 1.0;
const double SCALE_OVERHEAD_PER_BLOB = 0.05;

// [Formula] Dynamic Sample Verification Cost
// Physics: Verify 1 Sample = 1 Pairing (1.0) + Tiny linear overhead
formula COMPUTE_WEIGHT_SAMPLE = BASE_SAMPLE_COST + (TOTAL_BLOBS * SCALE_OVERHEAD_PER_BLOB);

// [Formula] Scaling & Penalties
formula scale_penalty = 1.0 + (window_size * 0.05) + (network_load * 0.02);
formula COL_SIZE_KB = (TOTAL_BLOBS * BLOB_SIZE_KB * EC_REDUNDANCY) / TOTAL_SUBNETS; 
formula upload_amp_factor = (network_load >= 4) ? 8.0 : ((network_load = 3) ? 4.0 : 2.0);
formula backoff_slots = BACKOFF_BASE + floor(pow(BACKOFF_EXP_BASE, fail_count));
formula congestion_factor_new = 1.0 + (network_load * 0.1);
formula latency_physics_cost = (TOTAL_BLOBS * COEFF_PEERDAS) * congestion_factor_new;

// [Formula] Waste Multiplier (Congestion impact on headers/retransmits)
formula waste_multiplier = (network_load <= 3) ? 1.0 : 
                           ((network_load = 4) ? 1.3 : 2.5);

// [Core Logic] Resource Interception Coefficient
const double FIREWALL_LEAKAGE = 0.1;
formula resource_factor = (trust_credit=1 | PENALTY_GRIEFING=0) ? 1.0 : FIREWALL_LEAKAGE;

// [Formula] Bandwidth Aux Variables
formula p_transmit_payload = (1.0 - p_mal) + (p_mal * strategy_p_disclosure);
formula p_payload_honest = p_hon * p_tx_success;
formula p_payload_griefing = p_mal * p_tx_success * strategy_p_griefing;
formula p_arrival_with_payload = p_payload_honest + p_payload_griefing;
formula p_send_payload_group = p_hon + (p_mal * strategy_p_griefing);
formula p_send_header_only_group = p_mal * strategy_p_disclosure;
formula p_payload_verification_ratio = p_hon + (p_mal * strategy_p_griefing);

// =========================================================================
// [5] System Module (PeerDAS Logic with Safety & Defense)
// =========================================================================
module System

    // --- State Variables -------------------------------------------------
    // stage: 0=Wait, 1=Sample, 2=Verified, 3=Remote_Repair
    stage : [0..3] init 0;
    step : [0..1] init 0;                           // 0: Protocol Action, 1: Env Update
    
    // Trust & Security State
    trust_credit : [0..1] init 0;                   // Node trust score
    suspicion_count : [0..MAX_SUSPICION] init 0;    // Intrusion suspicion counter
    subnet_state : [0..2] init 0;                   // 0: Eclipsed, 1: Safe, 2: Recovering
    
    // Sampling State
    window_size : [1..MAX_WINDOW] init 3;           // Current concurrent window
    k_samples : [0..CUSTODY_REQUIREMENT] init 0;
    unique_sources : [0..UNIQUE_SOURCES_NEEDED] init 0;
    
    // Process Flags
    gossip_waited : [0..1] init 0;                  // 0: Init, 1: Ready to Check
    custody_status : [0..1] init 0;                 // 0: Missing, 1: Available
    has_repeered : [0..1] init 1;                   // Flag for successful re-peering
    
    // Environment & Counters
    network_load : [0..MAX_NETWORK_LOAD] init START_LOAD;
    fail_count : [0..MAX_FAIL_TOLERANCE] init 0;    // Consecutive failure counter
    net_state : [0..1] init 0;                      // 0: Normal, 1: Congested
    backoff_timer : [0..40] init 0;                 // General purpose timer
    retry_count : [0..MAX_TOTAL_RETRIES] init 0;    // Repair retry counter

    // =========================================================================
    // [Stage 0: Initialization & Gossip Wait]
    // =========================================================================
    
    // [Step A: Start Wait] 
    [] (is_running) & (stage=0) & (step=0) & (backoff_timer=0) & (gossip_waited=0) -> 
        1.0 : 
            (backoff_timer' = GOSSIP_PROP_TICKS) & 
            (gossip_waited' = 1) &                  
            (step' = 1);

    // [Step B: Gossip Resolution]
    [] (is_running) & (stage=0) & (step=0) & (backoff_timer=0) & (gossip_waited=1) -> 
        
        // Branch 1: Block Header propagation success
        p_block_prop_success : 
            (stage' = 1) & 
            (custody_status' = 0) &  
            (step' = 1) +
            
        // Branch 2: Block Header lost
        (1.0 - p_block_prop_success) : 
            (stage' = 1) & 
            (custody_status' = 0) & 
            (backoff_timer' = COST_FETCH_HEADER) & 
            (step' = 1);

    // =========================================================================
    // [Action 0: Defense Mechanism - Forced Re-peering]
    // =========================================================================
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & 
       (
         (suspicion_count >= MAX_SUSPICION) | 
         ((fail_count >= MAX_FAIL_TOLERANCE))
       ) ->
        1.0 : 
            (subnet_state' = 2) &             // Enter Recovery State
            (has_repeered' = 1) & 
            (fail_count' = 0) & 
            (suspicion_count' = 0) & 
            (window_size' = 1) & 
            (unique_sources' = 0) & 
            (k_samples' = k_samples) & 
            (backoff_timer' = REPEER_DELAY) & 
            (step' = 1);

    // =========================================================================
    // [Action 1: Finalization & Repair Logic]
    // =========================================================================

    // [Action 1a: Attempt Finalization]
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (need_switch) & (suspicion_count < MAX_SUSPICION) & 
       (k_samples >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED) -> 
       
        // Branch A: Safe Success
        p_custody_success_safe :
            (stage' = 2) & 
            (custody_status' = 1) & 
            (fail_count' = 0) & 
            (backoff_timer' = 1) & 
            (step' = 1) +
            
        // Branch B: Success with Debt
        (1.0 - p_custody_success_safe) :
            (stage' = 2) & 
            (custody_status' = 0) & 
            (fail_count' = 0) &
            (backoff_timer' = 1) & 
            (step' = 1);

    // [Action 1b: Explicit Sampling Failure]
    // The node forces repair based solely on insufficient Unique Sources, regardless of environment.
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (suspicion_count < MAX_SUSPICION) & 
       (need_switch | (k_samples >= CUSTODY_REQUIREMENT)) &
       (
         (k_samples < CUSTODY_REQUIREMENT) | 
         (unique_sources < UNIQUE_SOURCES_NEEDED) 
       ) -> 
        1.0 : 
            (stage' = 3) & 
            (backoff_timer' = COST_DHT_REPAIR) & 
            (step' = 1);

    // [Action 1c: Timer Decrement]
    [] (is_running) & (stage>=0) & (step=0) & (backoff_timer > 0) ->
        1.0 : (backoff_timer' = backoff_timer - 1) & (step'=1);

    // [Action 1d: Repair Outcome]
    [] (is_running) & (stage=3) & (step=0) & (backoff_timer=0) ->
        
        // --- Branch A: Success ---
        P_REPAIR_OUTCOME : 
            (stage' = 2) & 
            (k_samples' = max(k_samples, CUSTODY_REQUIREMENT)) &
            (unique_sources' = max(unique_sources, UNIQUE_SOURCES_NEEDED)) &
            (custody_status' = 1) & 
            (fail_count' = 0) & 
            (retry_count' = 0) &
            (suspicion_count' = suspicion_count) & 
            (trust_credit' = 0) & 
            (step' = 1) +

        // --- Branch B: Retry with Smart Cleaning ---
        ((1.0 - P_REPAIR_OUTCOME) * ((retry_count < MAX_TOTAL_RETRIES) ? 1.0 : 0.0)) : 
            (stage' = 1) &                
            (fail_count' = 0) & 
            (retry_count' = retry_count + 1) & 
            (window_size' = 1) &          
            (backoff_timer' = COST_RETRY_DELAY) & 
            (suspicion_count' = min(MAX_SUSPICION, suspicion_count + 1)) &
            (trust_credit' = 0) &        
            (k_samples' = ((k_samples >= CUSTODY_REQUIREMENT) & (unique_sources < UNIQUE_SOURCES_NEEDED)) ? 0 : k_samples) & 
            (unique_sources' = ((k_samples >= CUSTODY_REQUIREMENT) & (unique_sources < UNIQUE_SOURCES_NEEDED)) ? 0 : unique_sources) &
            (step' = 1) +

        // --- Branch C: Hard Reset ---
        ((1.0 - P_REPAIR_OUTCOME) * ((retry_count >= MAX_TOTAL_RETRIES) ? 1.0 : 0.0)) : 
            (stage' = 0) & 
            (fail_count' = 0) & 
            (retry_count' = 0) &           
            (k_samples' = 0) & 
            (unique_sources' = 0) & 
            (window_size' = MAX_WINDOW) &             
            (suspicion_count' = MAX_SUSPICION) &
            (trust_credit' = 0) &
            (gossip_waited' = 0) & 
            (backoff_timer' = SLOT_PENALTY) & 
            (step' = 1);
    
    // [Action 0.5: Resolve Re-peering Result]
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (subnet_state=2) ->
        p_escape_success : 
           (subnet_state' = 1) & 
           (step' = 1) +
        (1.0 - p_escape_success) : 
            (subnet_state' = 0) & 
            (step' = 1);

    // =========================================================================
    // [Action 2: Window = 1] (Serial Mode with Trust & Sybil Logic)
    // =========================================================================
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (fail_count < MAX_FAIL_TOLERANCE) & (!need_switch) & (window_size=1) & (subnet_state != 2) & (suspicion_count < MAX_SUSPICION) ->
        
        // 2.1 Malicious: Griefing (Invalid Data)
        (p_mal * p_interaction_fails) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & 
            (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_GRIEFING)) & 
            (trust_credit' = 0) & 
            (window_size' = 1) & (stage' = stage) & (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
            
        // 2.2 Malicious: Silent (Timeout)
        (p_mal * p_bad_silent) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & 
            (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT)) & 
            (trust_credit' = 0) & 
            (window_size' = 1) & (backoff_timer' = (fail_count + 1 >= MAX_FAIL_TOLERANCE) ? 0 : TIMEOUT_DELAY) & (stage' = stage) & (step' = 1) +
            
        // 2.3 Malicious: Selective Disclosure (False Positive)
        (p_mal * p_disclosure_succeeds) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 1)) & 
            (fail_count' = 0) & 
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = 1) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (window_size' = 1) & (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +

        // 2.4 Honest: Valid Data (New Peer)
        (p_hon * p_log_valid * prob_find_new * p_eff_new) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = min(MAX_WINDOW, window_size+1)) & 
            (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE ) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = 1) & (step' = 1) +

        // 2.5 Honest: Valid Data (Old Peer)
        (p_hon * p_log_valid * (1-prob_find_new) * p_eff_old) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = unique_sources) & 
            (window_size' = min(MAX_WINDOW, window_size+1)) & 
            (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
            
        // 2.6 Honest: Data Missing / Peer Empty
        (p_hon * p_log_valid * (1.0 - (prob_find_new * p_eff_new) - ((1-prob_find_new) * p_eff_old))) : 
            (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = window_size) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (suspicion_count' = max(0, suspicion_count - 1)) & 
            (trust_credit' = trust_credit) & 
            (stage' = stage) & (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
            
        // 2.7 Honest: Physical Waste -> RPC Repair (Success)
         (p_hon * p_outcome_waste_good * P_RPC_EFFECTIVE) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = window_size) & 
            (fail_count' = 0) &            
         (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (backoff_timer' = COST_SUBNET_RPC) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

        // 2.8 Honest: Physical Waste -> RPC Repair (Fail -> DHT)
          (p_hon * p_outcome_waste_good * (1.0 - P_RPC_EFFECTIVE)) : 
          (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & 
          (window_size' = max(1, floor(window_size / 2))) &
          (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_MINOR)) &
          (trust_credit' = trust_credit) &
          (backoff_timer' = COST_DHT_REPAIR) &
          (stage' = stage) & (step' = 1) +
          
        // 2.9 Honest: Spin (Wait)
        (p_hon * p_hon_spin) : (trust_credit' = trust_credit) & (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1);

// =========================================================================
    // [Action 3: Window = 2
    // =========================================================================
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (fail_count < MAX_FAIL_TOLERANCE) & (!need_switch) & (window_size=2) & (subnet_state != 2) & (suspicion_count < MAX_SUSPICION) ->
        
        // --- 1. Malicious Branches ---
        (p_w2_all_mal * (1.0 - pow(1.0 - p_interaction_fails, 2))) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_GRIEFING)) & (trust_credit' = 0) & (window_size' = 1) & (stage' = stage) & (step' = 1) +

        (p_w2_all_mal * (pow(p_bad_silent + p_disclosure_succeeds, 2) - pow(p_disclosure_succeeds, 2))) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT)) & (trust_credit' = 0) & (window_size' = 1) & (backoff_timer' = (fail_count + 1 >= MAX_FAIL_TOLERANCE) ? 0 : TIMEOUT_DELAY) & (stage' = stage) & (step' = 1) +

        (p_w2_all_mal * pow(p_disclosure_succeeds, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 2)) & 
            (fail_count' = 0) & 
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = 1) &
            (window_size' = 1) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 2) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

        // --- 2. Mixed Branches ---
        
        // [Mixed Success A]
        (p_w2_mix_slow * p_log_valid * p_eff_new) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = 0) & (window_size' = 2) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +

        // [Mixed Failure A]
        (p_w2_mix_slow * (1.0 - (p_log_valid * p_eff_new))) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = (network_load < HIGH_USAGE_THRES) ? min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT) : suspicion_count) & (trust_credit' = 0) & (window_size' = 1) & (backoff_timer' = (fail_count + 1 >= MAX_FAIL_TOLERANCE) ? 0 : TIMEOUT_DELAY) & (stage' = stage) & (step' = 1) +
            
        // [Mixed Success B]
        (p_w2_mix_disc * p_log_valid * p_eff_new) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0) + 1)) & 
            (fail_count' = 0) & (window_size' = 2) & 
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0) + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT )&(step' = 1) +

        (p_w2_mix_fail * p_log_valid * p_eff_new) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = 0) & (window_size' = 2) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT )&(step' = 1) +
            
        // [Mixed Failure B]
        ((p_w2_mix_disc + p_w2_mix_fail) * (1.0 - (p_log_valid * p_eff_new))) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = (network_load < HIGH_USAGE_THRES) ? min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT) : suspicion_count) & (trust_credit' = 0) & (window_size' = 1) & (stage' = stage) & (step' = 1) +

        // --- 3. Honest Branches ---

        // [CASE A: All Valid Success]
        // A.1: 2 New
        (p_w2_all_hon * pow(p_log_valid, 2) * prob_s2_2 * pow(p_eff_new, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0))) & 
            (window_size' = min(MAX_WINDOW, window_size+1)) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
        
        // A.2: 1 New 1 Old
        (p_w2_all_hon * pow(p_log_valid, 2) * prob_s2_1 * p_eff_new * p_eff_old) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = min(MAX_WINDOW, window_size+1)) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.3: 1 New 1 Old(Empty)
        (p_w2_all_hon * pow(p_log_valid, 2) * prob_s2_1 * p_eff_new * (1-p_eff_old)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = min(MAX_WINDOW, window_size+1)) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.4: 2 Old
        (p_w2_all_hon * pow(p_log_valid, 2) * prob_s2_0 * pow(p_eff_old, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & (unique_sources' = unique_sources) & (window_size' = min(MAX_WINDOW, window_size+1)) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - 1) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.5: 2 Old (1 Empty)
        (p_w2_all_hon * pow(p_log_valid, 2) * prob_s2_0 * 2 * p_eff_old * (1-p_eff_old)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & (unique_sources' = unique_sources) & (window_size' = min(MAX_WINDOW, window_size+1)) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // A.6: 2 Old (Both Empty)
        (p_w2_all_hon * pow(p_log_valid, 2) * prob_s2_0 * pow(1-p_eff_old, 2)) : 
            (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = window_size) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = trust_credit) & 
            (stage' = stage) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +

        // [CASE B: 1 Phys Success, 1 Phys Fail] (Partial Success)
        
        // B.1: 1 New (Valid)
        (p_w2_all_hon * (2 * p_phys_tx * p_outcome_waste_good) * prob_find_new * p_eff_new) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
            
        // B.2: 1 Old (Valid)
        (p_w2_all_hon * (2 * p_phys_tx * p_outcome_waste_good) * (1-prob_find_new) * p_eff_old) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
            
        // B.3: 1 Old (Empty)
        (p_w2_all_hon * (2 * p_phys_tx * p_outcome_waste_good) * (1.0 - (prob_find_new * p_eff_new) - ((1-prob_find_new) * p_eff_old))) : 
            (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (suspicion_count' = (network_load < HIGH_USAGE_THRES) ? min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT) : max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = trust_credit) & 
            (stage' = stage) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
            
       // [CASE C: All Fail (Physical)] -> Try RPC Repair

      // RPC Success
         (p_w2_all_hon * pow(p_outcome_waste_good, 2) * P_RPC_EFFECTIVE) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (backoff_timer' = COST_SUBNET_RPC) &
            (window_size' = max(1, floor(window_size/2))) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

      // RPC Fail
         (p_w2_all_hon * pow(p_outcome_waste_good, 2) * (1.0 - P_RPC_EFFECTIVE)) : 
         (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & 
         (window_size' = max(1, floor(window_size/2))) & 
         (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_MINOR)) &
         (trust_credit' = trust_credit) & 
         (backoff_timer' = COST_DHT_REPAIR) & 
         (stage' = stage) & (step' = 1) +

        // [Spinning Complement] 
       (p_w2_all_hon * max(0.0, pow(p_phys_tx, 2) - pow(p_log_valid, 2))) : (trust_credit' = trust_credit) & (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1);

    // =========================================================================
    // [Action 4: Window = 3] 
    // =========================================================================
    [] (is_running) & (step=0) & (stage=1) & (backoff_timer=0) & (fail_count < MAX_FAIL_TOLERANCE) & (!need_switch) & (window_size=3) & (subnet_state != 2) & (suspicion_count < MAX_SUSPICION) ->
        
        // --- [Attack Branch] ---        
        (p_w3_all_mal * (1.0 - pow(1.0 - p_interaction_fails, 3))) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_GRIEFING)) & (trust_credit' = 0) & (window_size' = 1) & (stage' = stage) & (step' = 1) +
        (p_w3_all_mal * (pow(p_bad_silent + p_disclosure_succeeds, 3) - pow(p_disclosure_succeeds, 3))) : 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT)) & (trust_credit' = 0) & (window_size' = 1) & (backoff_timer' = (fail_count + 1 >= MAX_FAIL_TOLERANCE) ? 0 : TIMEOUT_DELAY) & (stage' = stage) & (step' = 1) +

        // 3 Malicious nodes succeed
        (p_w3_all_mal * pow(p_disclosure_succeeds, 3)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+3)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + 3)) & 
            (fail_count' = 0) & 
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = 1) &
            (window_size' = 1) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 3) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

        // --- Mixed Scenarios (Original Simplified) ---
        
        // Scene A: 2 Bad 1 Good (Success)
        (p_w3_2b1g_slow * p_log_valid * p_eff_new) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = 0) & (window_size' = 1) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
            
        // Scene A: 2 Bad 1 Good (Fail)
        (p_w3_2b1g_slow * (1.0 - (p_log_valid * p_eff_new))) :
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = (network_load < HIGH_USAGE_THRES) ? min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT) : suspicion_count) & (trust_credit' = 0) & (window_size' = 1) & (backoff_timer' = (fail_count + 1 >= MAX_FAIL_TOLERANCE) ? 0 : TIMEOUT_DELAY) & (stage' = stage) & (step' = 1) +

        // Scene B: 1 Bad 2 Good (Success)
        (p_w3_1b2g_slow * pow(p_log_valid * p_eff_new, 2)) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0))) & 
            (fail_count' = 0) & (window_size' = 3) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
        
        // Scene B: 1 Bad 2 Good (Partial Fail)
        (p_w3_1b2g_slow * 2 * (p_log_valid * p_eff_new) * (1.0 - (p_log_valid * p_eff_new))) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (window_size' = 1) & 
            (suspicion_count' = max(0, suspicion_count - 1)) &
            (trust_credit' = 0) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
        
        // Scene B: 1 Bad 2 Good (Fail)
        (p_w3_1b2g_slow * pow(1.0 - (p_log_valid * p_eff_new), 2)) :
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = (network_load < HIGH_USAGE_THRES) ? min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT) : suspicion_count) & (trust_credit' = 0) & (window_size' = 1) & (backoff_timer' = (fail_count + 1 >= MAX_FAIL_TOLERANCE) ? 0 : TIMEOUT_DELAY) & (stage' = stage) & (step' = 1) +

        // Other Mixed (Success -> Split)
        ((p_w3_2b_2disc + p_w3_2b_1disc + p_w3_2b_0disc) * p_log_valid * p_eff_new) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = 0) & (window_size' = 1) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +
            
        // Other Mixed (Fail)
        ((p_w3_2b_2disc + p_w3_2b_1disc + p_w3_2b_0disc) * (1.0 - (p_log_valid * p_eff_new))) : (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT)) & (trust_credit' = 0) & (window_size' = 1) & (stage' = stage) & (step' = 1) +
        
        // Other Mixed (Double Success)
        ((p_w3_1b_1disc + p_w3_1b_0disc) * pow(p_log_valid * p_eff_new, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0))) & 
            (fail_count' = 0) & (window_size' = 3) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +           
        
        // Other Mixed (Partial)
        ((p_w3_1b_1disc + p_w3_1b_0disc) * 2 * (p_log_valid * p_eff_new) * (1.0 - (p_log_valid * p_eff_new))) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (window_size' = max(1, floor(window_size/2))) & 
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) &
            (trust_credit' = 0) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +      
        
        // Other Mixed (Fail)
        ((p_w3_1b_1disc + p_w3_1b_0disc) * pow(1.0 - (p_log_valid * p_eff_new), 2)) : (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & (suspicion_count' = (network_load < HIGH_USAGE_THRES) ? min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT) : suspicion_count) & (trust_credit' = 0) & (window_size' = 1) & (stage' = stage) & (step' = 1) +

        // --- [Honest Branch]  ---
        
        // CASE A: 3 Success (All valid)
        
        // 1. [3 New]
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_3 * pow(p_eff_new, 3)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+3)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?3:0))) & 
            (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?3:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +

        // 2. [2 New + 1 Old]
        // 2.1 Old Peer Has Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_2 * p_eff_old * pow(p_eff_new, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+3)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0))) & 
            (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +

        // 2.2 Old Peer Empty
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_2 * (1-p_eff_old) * pow(p_eff_new, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0))) & 
            (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +

        // 3. [1 New + 2 Old]
        // 3.1 Two Old Peers Have Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_1 * p_eff_new * pow(p_eff_old, 2)) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+3)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
        
        // 3.2 One Old Peer Has Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_1 * p_eff_new * 2 * p_eff_old * (1-p_eff_old)) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
        
        // 3.3 Zero Old Peers Have Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_1 * p_eff_new * pow(1-p_eff_old, 2)) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +

        // 4. [3 Old]
        // 4.1 Three Old Peers Have Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_0 * pow(p_eff_old, 3)) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+3)) & (unique_sources' = unique_sources) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 3) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // 4.2 Two Old Peers Have Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_0 * 3 * pow(p_eff_old, 2) * (1-p_eff_old)) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & (unique_sources' = unique_sources) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (step' = 1) +
        
        // 4.3 One Old Peer Has Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_0 * 3 * p_eff_old * pow(1-p_eff_old, 2)) :
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & (unique_sources' = unique_sources) & (window_size' = MAX_WINDOW) & (fail_count' = 0) & 
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // 4.4 Zero Old Peers Have Data
        (p_w3_all_hon * pow(p_log_valid, 3) * prob_s3_0 * pow(1-p_eff_old, 3)) :
            (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = window_size) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = trust_credit) & 
            (stage' = stage) &(backoff_timer' = 1) & (step' = 1) +

        // [CASE B: 2 Phys Success, 1 Phys Fail] (Partial Success -> Split)
        
        // 1.1 [2 New]
        (p_w3_all_hon * 3 * pow(p_phys_tx, 2) * p_outcome_waste_good * prob_s2_2 * pow(p_eff_new, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0))) & 
            (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?2:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // 1.2 [1 New + 1 Old (Valid)]
        (p_w3_all_hon * 3 * pow(p_phys_tx, 2) * p_outcome_waste_good * prob_s2_1 * p_eff_new * p_eff_old) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
        
        // 1.3 [2 Old (Valid)]
        (p_w3_all_hon * 3 * pow(p_phys_tx, 2) * p_outcome_waste_good * prob_s2_0 * pow(p_eff_old, 2)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+2)) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 2) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +

        // 2.1 [1 New + 1 Old (Invalid)]
        (p_w3_all_hon * 3 * pow(p_phys_tx, 2) * p_outcome_waste_good * prob_s2_1 * p_eff_new * (1-p_eff_old)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources+1)) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + 1) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & (backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +
        
        // 2.2 [1 Old (Valid) + 1 Old (Invalid)]
        (p_w3_all_hon * 3 * pow(p_phys_tx, 2) * p_outcome_waste_good * prob_s2_0 * 2 * p_eff_old * (1-p_eff_old)) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) &(step' = 1) +

        // 3. Zero Valid Samples (2 Old Invalid)
        // Physical loss causes empty data, retain trust
        (p_w3_all_hon * 3 * pow(p_phys_tx, 2) * p_outcome_waste_good * prob_s2_0 * pow(1-p_eff_old, 2)) : 
            (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
          (suspicion_count' = max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = trust_credit) & 
            (stage' = stage) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +

        // [CASE C: 1 Phys Success, 2 Phys Fail] (1 Success -> Split)
        
        // 1. [1 New]
        (p_w3_all_hon * 3 * p_phys_tx * pow(p_outcome_waste_good, 2) * prob_find_new * p_eff_new) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
        
        // 2. [1 Old (Valid)]
        (p_w3_all_hon * 3 * p_phys_tx * pow(p_outcome_waste_good, 2) * (1-prob_find_new) * p_eff_old) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (unique_sources >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +
            
        // 3. [1 Old (Invalid)] 
        (p_w3_all_hon * 3 * p_phys_tx * pow(p_outcome_waste_good, 2) * (1-prob_find_new) * (1-p_eff_old)) : 
            (k_samples' = k_samples) & (unique_sources' = unique_sources) & (window_size' = max(1, floor(window_size/2))) & (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (suspicion_count' = (network_load < HIGH_USAGE_THRES) ? min(MAX_SUSPICION, suspicion_count + PENALTY_SILENT) : max(0, suspicion_count - DECAY_RATE)) & 
            (trust_credit' = trust_credit) & 
            (stage' = stage) &(backoff_timer' = COST_SAMPLE_RTT) & (step' = 1) +

       // [CASE D: All Phys Fail] -> Try RPC Repair

       // RPC Success
        (p_w3_all_hon * pow(p_outcome_waste_good, 3) * P_RPC_EFFECTIVE) : 
            (k_samples' = min(CUSTODY_REQUIREMENT, k_samples+1)) & 
            (unique_sources' = min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0))) & 
            (fail_count' = 0) & 
            (suspicion_count' = (trust_credit=1) ? max(0, suspicion_count - DECAY_RATE) : suspicion_count) &
            (trust_credit' = (trust_credit=1) ? 0 : 1) &
            (backoff_timer' = COST_SUBNET_RPC) &
            (window_size' = max(1, floor(window_size/2))) & 
            (stage' = ((min(CUSTODY_REQUIREMENT, k_samples + 1) >= CUSTODY_REQUIREMENT) & (min(UNIQUE_SOURCES_NEEDED, unique_sources + (subnet_state!=0?1:0)) >= UNIQUE_SOURCES_NEEDED)) ? 2 : 1) & 
            (step' = 1) +

     // RPC Fail
       (p_w3_all_hon * pow(p_outcome_waste_good, 3) * (1.0 - P_RPC_EFFECTIVE)) : 
       (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count+1)) & 
       (window_size' = max(1, floor(window_size/2))) & 
       (suspicion_count' = min(MAX_SUSPICION, suspicion_count + PENALTY_MINOR)) &
       (trust_credit' = trust_credit) & 
       (backoff_timer' = COST_DHT_REPAIR) & 
       (stage' = stage) & (step' = 1) +

        // [Spinning Complement]
       (p_w3_all_hon * max(0.0, pow(p_phys_tx, 3) - pow(p_log_valid, 3))) :(trust_credit' = trust_credit) & (backoff_timer' = COST_SAMPLE_RTT) & (step' = 1);

    // =========================================================================
    // [Action 5: Stage 2 Background Repair]
    // =========================================================================
    [] (stage=2) & (step=0) & (custody_status=0) ->
        P_REPAIR_OUTCOME : 
            (custody_status' = 1) & 
            (fail_count' = 0) & 
            (step' = 0) +
        (1.0 - P_REPAIR_OUTCOME ) : 
            (custody_status' = 0) & 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (step' = 0) ;

    // =========================================================================
    // [Step 1: Environment Update]
    // =========================================================================
    [] (is_running) & (step=1) ->
        (p_matrix_spike * p_int) : (step'=0) & 
            (network_load' = min(MAX_NETWORK_LOAD, network_load + 1)) & 
            (net_state' = (min(MAX_NETWORK_LOAD, network_load + 1) >= HIGH_USAGE_THRES) ? 1 : net_state) & 
            (subnet_state' = (p_malicious_init > 0 & subnet_state=1) ? 0 : subnet_state) +
        (p_matrix_spike * (1.0 - p_int)) : (step'=0) & 
            (network_load' = min(MAX_NETWORK_LOAD, network_load + 1)) & 
            (net_state' = (min(MAX_NETWORK_LOAD, network_load + 1) >= HIGH_USAGE_THRES) ? 1 : net_state) & 
            (subnet_state' = subnet_state) +
            
        (p_matrix_ease * p_int) : (step'=0) & 
            (network_load' = max(0, network_load - 1)) & 
            (net_state' = ((max(0, network_load - 1) >= HIGH_USAGE_THRES) ? 1 : 0)) & 
            (subnet_state' = (p_malicious_init > 0 & subnet_state=1) ? 0 : subnet_state) + 
        (p_matrix_ease * (1.0 - p_int)) : (step'=0) & 
            (network_load' = max(0, network_load - 1)) & 
            (net_state' = ((max(0, network_load - 1) >= HIGH_USAGE_THRES) ? 1 : 0)) & 
            (subnet_state' = subnet_state) +

        (p_matrix_stay * p_int) : (step'=0) & 
            (net_state' = (is_high_usage ? 1 : 0)) & 
            (subnet_state' = (p_malicious_init > 0 & subnet_state=1) ? 0 : subnet_state) + 
        (p_matrix_stay * (1.0 - p_int)) : (step'=0) & 
            (net_state' = (is_high_usage ? 1 : 0)) & 
            (subnet_state' = subnet_state);

    // [Sink State]
    [] (!is_running) & (custody_status=1) -> 1.0 : (stage' = stage) & (step' = 0);
    [] (stage=2) & (step=1) -> 1.0 : (step'=0);

endmodule
// =========================================================================
// [6] Rewards
// =========================================================================

rewards "compute_cost"
    //  Sampling & Verification Phase (Stage 1)
    [] (step=0) & (stage=1) & (is_running) & (backoff_timer=0) & (!need_switch) : 
        window_size * scale_penalty * (
            // 1. Honest Interaction
            // Verify valid sample (1.0 NCU) + Physical spin loss
            (p_hon * p_log_valid * COMPUTE_WEIGHT_SAMPLE) + 
            (p_hon * p_hon_spin * (COMPUTE_WEIGHT_SAMPLE * 0.1)) +
            
            // 2. Malicious Interaction
            // Attacker sends garbage (Griefing) or private data (Private)
            (p_mal * strategy_p_griefing * max(p_tx_success, MIN_ATTACK_CPU_LOAD) * COMPUTE_WEIGHT_SAMPLE * resource_factor) + 
            (p_mal * strategy_p_disclosure * max(p_tx_success, MIN_ATTACK_CPU_LOAD) * COMPUTE_WEIGHT_SAMPLE * resource_factor)
        ) +
        
        // 3. RPC Rescue Verification
        // Triggered only on physical failure, usually for honest nodes
        ((window_size=1) ? (p_hon * p_outcome_waste_good * P_RPC_EFFECTIVE * COMPUTE_WEIGHT_SAMPLE) : 0) +
        ((window_size=2) ? (p_w2_all_hon * pow(p_outcome_waste_good, 2) * P_RPC_EFFECTIVE * COMPUTE_WEIGHT_SAMPLE) : 0) +
        ((window_size=3) ? (p_w3_all_hon * pow(p_outcome_waste_good, 3) * P_RPC_EFFECTIVE * COMPUTE_WEIGHT_SAMPLE) : 0);

     // Remote Repair Verification (Stage 3)
     // Logic: Repair missing parts, verification cost is Sample-level (1.0+)
     [] (stage=3) & (step=0) & (backoff_timer=0) : 
        (max(0, CUSTODY_REQUIREMENT - k_samples) * COMPUTE_WEIGHT_SAMPLE);
endrewards

rewards "bandwidth_usage"
    //  Sampling Phase Bandwidth (Stage 1)
    [] (step=0) & (stage=1) & (is_running) & (backoff_timer=0) & (!need_switch) :
        window_size * (
             // Honest node: Download full data (header + erasure codes)
             (p_hon * p_log_valid * COL_SIZE_KB) +      
             // Malicious node: Garbage traffic
             // If defense active (resource_factor=0.1), truncate at handshake, consuming only 10% bandwidth
             (p_mal * (strategy_p_griefing + strategy_p_disclosure) * COL_SIZE_KB * resource_factor)
        ) * waste_multiplier; // Multiply by congestion coefficient

    //  Header Fetch (Gossip Phase)
    [] (stage=0) & (step=0) & (gossip_waited=1) :
        p_block_prop_success * (CUSTODY_REQUIREMENT * COL_SIZE_KB * upload_amp_factor * waste_multiplier);

    //  Repair Phase Bandwidth (Stage 3 Entry)
    // Logic: Pay total bandwidth for "Query Signal + Data Download" when entering repair state
    [] (stage=1) & (step=0) & (backoff_timer=0) & 
       (need_switch | (k_samples >= CUSTODY_REQUIREMENT)) &
       (k_samples < CUSTODY_REQUIREMENT | unique_sources < UNIQUE_SOURCES_NEEDED) :
       
       // 1. Data part: Repair missing parts, multiply by 1.1 (protocol header)
       (max(0, CUSTODY_REQUIREMENT - k_samples) * COL_SIZE_KB * 1.1 * waste_multiplier) +
       
       // 2. Signaling part: DHT query overhead (one-time)
       (DHT_QUERY_KB * 1.5 * waste_multiplier);

    // Background Cyclic Repair (Stage 2)
    // Corresponds to Action 5, each attempt consumes 10% bandwidth
    [] (stage=2) & (step=0) & (custody_status=0) :
        (CUSTODY_REQUIREMENT * COL_SIZE_KB * 0.10 * waste_multiplier);
endrewards

rewards "latency_rtts"
    //  Physical Time
    (is_running) & (step=0) & (backoff_timer > 0) : 1;
    
    // Congestion Queuing
    (is_running) & (step=0) & (backoff_timer > 0) & (network_load > 2) : 
        (network_load - 2) * CONGESTION_DELAY_COEFF;
    
    // Final Verification Latency
    [] (stage=2) & (step=1) : latency_physics_cost;
endrewards

// =========================================================================
// [7] Labels
// =========================================================================

// [Liveness Metric]: Overall Success Rate
label "success" = (stage=2) & (step=0);

// [Safety Metric - Core]: False Positive Vote
label "false_positive_vote" = (stage=2) & (subnet_state=0);

// [Performance Metric]: Complete Success
label "complete_success" = (stage=2) & (custody_status=1);

// [Decoupling Metric]: Success with Debt
label "attestation_with_debt" = (stage=2) & (custody_status=0);

// [Failure Metric]: DoS Give-up
label "dos_giveup" = (stage=0) & (retry_count=0) & (backoff_timer=SLOT_PENALTY) & (step=1);

// [Safety Metric]: Escape Success
label "escape_success" = (subnet_state=1) & (has_repeered=1);
