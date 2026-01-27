// =========================================================================
// Model 1: EIP-4844 Baseline
// =========================================================================

dtmc

// =========================================================================
// [1] Experiment Control & Network Environment
// =========================================================================

// --- Experiment Variables ------------------------------------------------
const int MAX_NETWORK_LOAD = 5;       // Network congestion level cap (0-5)
const int START_LOAD = 2;             // [Variable] Initial network load
const int HIGH_USAGE_THRES = 2;       // High load threshold (for stats)
const int TOTAL_BLOBS = 6;            // Total Blobs per Slot
const int MAX_TOTAL_RETRIES = 1;      // Maximum allowed retries
const int MAX_FAIL_TOLERANCE = 4;     // Max consecutive failure tolerance

// --- State & Logic Formulas ----------------------------------------------
formula is_running = (stage != 2) & (retry_count <= MAX_TOTAL_RETRIES);
formula is_success = (stage = 2);
formula is_high_usage = (network_load >= HIGH_USAGE_THRES);
formula need_switch = (fail_count >= MAX_FAIL_TOLERANCE);
formula rem_blobs = max(0, TOTAL_BLOBS - blobs_downloaded);

// --- Traffic Pressure & Endogenous Feedback ------------------------------

// Traffic Pressure: Higher blob count = Higher bandwidth occupation
formula traffic_pressure = rem_blobs / TOTAL_BLOBS;
// Endogenous Deterioration (Spike)
// Coefficient 0.15: Large packets stress the congestion window
formula p_endo_spike = (network_load >= MAX_NETWORK_LOAD) ? 0.0 : 
                       min(0.90, 0.05 + (0.15 * traffic_pressure));

// Endogenous Recovery (Ease)
// Physics: Base recovery 0.6, Resistance coefficient 0.15
formula bg_recovery_cap = 1.0 - (network_load / 6.0); 
formula raw_endo_ease = (0.6 * bg_recovery_cap) - (0.15 * traffic_pressure);
formula p_endo_ease = (network_load >= MAX_NETWORK_LOAD) ? 0.04 : 
                      ((network_load = 0) ? 0.0 : 
                      min(max(0.05, raw_endo_ease), max(0.0, 1.0 - p_endo_spike)));

formula p_endo_stay = max(0.0, 1.0 - p_endo_spike - p_endo_ease);

// =========================================================================
// [2] Time & Latency Parameters (Unit: RTTs)
// =========================================================================
const int GOSSIP_PROP_TICKS = 1;      // Wait time for Gossip propagation
const int COST_GOSSIP_RTT = 2;        // Base cost: Gossip tx + validation
const int COST_RPC_RTT = 5;           // RPC RTT (Lookup + Handshake)
const int COST_RETRY_DELAY = 2;       // Cooldown before retry
const int SLOT_PENALTY = 40;          // 4.0s Attestation Deadline (20 RTTs)
const int SLOT_DEADLINE = 20;         // Slot voting deadline
const int SLOT_TICKS = 60;            // 1 slot duration
const int MAX_TIMER_LIMIT = 40;       // Anti-deadlock timer cap

// =========================================================================
// [3] Physics Layer & Flow Control Formulas
// =========================================================================

// --- Base Physics Constants ----------------------------------------------
const double PACKET_LOSS_RATE = 0.01;      // Base physical link loss
const double BASE_SUCCESS = 1 - PACKET_LOSS_RATE; 
const double BASE_GOSSIP_PROB = 0.98 * (1.0 - PACKET_LOSS_RATE);  // Base discovery prob
const double EXT_LOSS_PENALTY = 0.2;       // Env deterioration penalty
const double SIZE_PENALTY = 0.05;          // Large packet penalty
const double MIN_TX_SUCCESS = 0.001;       // Min success floor
const double DISCOVERY_LOAD_DECAY = 0.02;  // Discovery decay by load
const double TCP_FRAGILITY_RATIO = 2.0;    // TCP fragility under load
const double BASE_CONGESTION_FACTOR = 0.02;// Base congestion factor

// --- Dynamic Stream Physics Models ---------------------------------------

// Stream Collapse: Exponential timeout rise
formula p_stream_collapse_prob = (network_load <= 2) ? 0.0 : 
                                 max(0.0, 1.0 - pow(0.4, network_load - 2.5));

// Stall Probability: Zombie connections (Handshake OK, BW 0)
formula p_raw_stall = max((network_load <= 2 ? 0.0 : network_load * 0.025), PACKET_LOSS_RATE * 0.8);

// Stream Cutoff Distribution: "Header only" vs "Partial"
formula ratio_partial = min(0.95, max(0.0, (0.9 - (network_load * 0.15) - (PACKET_LOSS_RATE * 4.0))));

// --- Congestion Survival Curves ------------------------------------------

// Base MTU Survival Rate (Small packet baseline)
formula p_mtu_survival = (network_load <= 1) ? 0.971 : 
                        ((network_load = 2) ? 0.818 : 
                        ((network_load = 3) ? 0.622 : 
                        ((network_load = 4) ? 0.378 : 0.182)));

// Packet Size Cliffs (Large packets decay cubically)
formula small_packet_cliff = p_mtu_survival;
formula large_packet_cliff = pow(p_mtu_survival, 3.0); 

// --- High-Level Probability Curves ---------------------------------------

// Subnet RPC Success (L4 = 0.40)
formula p_rpc_success = (network_load <= 2) ? 0.98 : 
                        ((network_load = 3) ? 0.80 : 
                        ((network_load = 4) ? 0.40 : 0.01));

// Block Propagation (Sigmoid Curve)
formula p_block_prop_success = (network_load <= 2) ? 1.0 :
                               ((network_load = 3) ? 0.95 :
                               ((network_load = 4) ? 0.70 : 0.30));

// --- Comprehensive Transmission Calculations -----------------------------
formula coupon_efficiency = max(0.05, rem_blobs / (TOTAL_BLOBS * 1.0));
formula decay_factor = pow(0.6, fail_count);
formula p_hot_start = max(0.2, decay_factor);

formula effective_blob_count = (1.0 + (network_load * 0.5)) * max(1.0, rem_blobs / PIPELINE_CONCURRENCY);
formula p_single_subnet_disc = max(MIN_TX_SUCCESS, (BASE_GOSSIP_PROB - (network_load * DISCOVERY_LOAD_DECAY)) * small_packet_cliff);
formula p_gossip_corr_factor = max(0.2, 1.0 - (network_load * 0.1));
formula p_gossip_arrival = pow(p_single_subnet_disc, effective_blob_count) * p_gossip_corr_factor;

formula dyn_self_cong_factor = 0.01 + (network_load * 0.02);
formula self_congestion = (rem_blobs / 6.0) * dyn_self_cong_factor;
formula internal_penalty = (pow(network_load, 2) * BASE_CONGESTION_FACTOR * TCP_FRAGILITY_RATIO) + self_congestion;
formula external_penalty = (net_state=1) ? EXT_LOSS_PENALTY : 0.0;

formula p_single_blob_tx = max(MIN_TX_SUCCESS, (BASE_SUCCESS - internal_penalty - external_penalty - SIZE_PENALTY) * large_packet_cliff * coupon_efficiency);

// Final Outcome Probabilities
formula p_tx_if_stream_alive = p_single_blob_tx;
formula p_raw_get_all = pow(p_tx_if_stream_alive, effective_blob_count);
formula p_get_all = (1.0 - p_stream_collapse_prob) * p_raw_get_all;
formula p_stalled_fail = p_stream_collapse_prob + ((1.0 - p_stream_collapse_prob) * p_raw_stall);
formula p_fragmented_total = max(0.0, 1.0 - p_get_all - p_stalled_fail);
formula p_get_partial = p_fragmented_total * ratio_partial;
formula p_get_tiny = p_fragmented_total * (1.0 - ratio_partial);

// =========================================================================
// [4] Resources & Cost Parameters
// =========================================================================
const double BLOB_SIZE_KB = 128.0;       // Single Blob size (KB)
const double GOSSIP_META_KB = 0.2;       // Gossip metadata overhead (KB)
const double DISCOVERY_OVERHEAD_KB = 5.0;// Discovery base bandwidth (KB)
const double COMPUTE_WEIGHT_BLOB = 4.0;  // Validation weight per Blob
const int KZG_CPU_PENALTY_FACTOR = 1;    // CPU penalty under congestion
const double PIPELINE_CONCURRENCY = 3.0; // Validation concurrency
const double COEFF_OLD_PROTOCOL = 3.072; // EIP-4844 latency coeff
const double BASE_AMP_FACTOR = 4.5;      // Bandwidth amplification

// --- Dynamic Cost Variables ----------------------------------------------
formula meta_storm_factor = (network_load <= 2) ? 1.0 : pow(3.0, network_load - 2);
formula raw_kzg_delay = (network_load >= 3) ? pow(network_load, 1.2) * KZG_CPU_PENALTY_FACTOR : 0;
formula current_kzg_delay_int = ceil(raw_kzg_delay); 
formula effective_transfer_cost = COST_GOSSIP_RTT + current_kzg_delay_int;
formula dynamic_amp_factor = ((network_load >= 4) ? 12.0 : ((network_load = 3) ? 6.0 : BASE_AMP_FACTOR)) * (0.8 + (TOTAL_BLOBS / 30.0));
formula congestion_factor = 1.0 + (network_load * 0.15);
formula latency_cost_old = ((TOTAL_BLOBS / PIPELINE_CONCURRENCY) * COEFF_OLD_PROTOCOL) * congestion_factor;
formula gossip_pruning_penalty = (network_load >= 5) ? 2 : 1;
formula saturation_penalty = 1.0 + (max(0, TOTAL_BLOBS - 6.0) / 64.0) * 0.3;

// =========================================================================
// [5] System Module (Strict 2-Step = 1-RTT Alignment)
// =========================================================================
module System

    // State Variables
    stage : [0..3] init 0;    // 0:Wait/Gossip, 1:Verify, 2:Success, 3:RPC
    step : [0..1] init 0;     // 0:Logic/Time, 1:Environment
    timer_tick : [0..MAX_TIMER_LIMIT] init 0;

    network_load : [0..MAX_NETWORK_LOAD] init START_LOAD;
    blobs_downloaded : [0..TOTAL_BLOBS] init 0;
    block_arrived : [0..1] init 0;

    fail_count : [0..MAX_FAIL_TOLERANCE] init 0;
    retry_count : [0..MAX_TOTAL_RETRIES] init 0;
    net_state : [0..1] init 0;

    // [Time Mechanism] Consumes physical time (2 Steps = 1 RTT)
    [] (is_running) & (step=0) & (timer_tick > 0) ->
        1.0 : (timer_tick' = timer_tick - 1) & (step' = 1);

    // ---------------------------------------------------------------------
    // [Stage 0: Entry & Gossip Wait]
    // ---------------------------------------------------------------------
    
    // [Init Decision] - Instant
    [] (is_running) & (stage=0) & (step=0) & (timer_tick=0) & 
       (blobs_downloaded < TOTAL_BLOBS) & (!need_switch) & (retry_count=0 & fail_count=0) -> 
       // Hot Start
       p_hot_start : 
            (stage' = 1) & 
            (timer_tick' = COST_GOSSIP_RTT) & 
            (step' = 1) +
       // Cold Start
       (1.0 - p_hot_start) : 
            (stage' = 0) & 
            (timer_tick' = GOSSIP_PROP_TICKS) & 
            (step' = 1);

    // [Gossip Outcome] - After Propagation
    // Condition (!need_switch) ensures priority over Global Penalty
    [] (is_running) & (stage=0) & (step=0) & (timer_tick=0) & 
       (blobs_downloaded < TOTAL_BLOBS) & (!need_switch) ->
        // A: Block & Blobs -> Verify
        (p_gossip_arrival * p_block_prop_success) :
            (block_arrived' = 1) &
            (stage' = 1) &
            (timer_tick' = effective_transfer_cost) &
            (step' = 1) +
        // B: Blobs Only -> Verify
        (p_gossip_arrival * (1.0 - p_block_prop_success)) :
            (block_arrived' = 0) &
            (stage' = 1) &
            (timer_tick' = effective_transfer_cost) &
            (step' = 1) +
        // C: Lost -> RPC
        (1.0 - p_gossip_arrival) :
            (stage' = 3) &
            (timer_tick' = COST_RPC_RTT) &
            (step' = 1);

    // ---------------------------------------------------------------------
    // [Stage 1: Processing & Validation]
    // ---------------------------------------------------------------------
    
    [] (is_running) & (stage=1) & (step=0) & (timer_tick=0) ->
        // 1. Success
        (p_get_all * p_block_prop_success) :
            (blobs_downloaded' = TOTAL_BLOBS) & (block_arrived' = 1) & (fail_count' = 0) &
            (stage' = 2) & (step' = 1) +

        // 2. Missing Block -> RPC
        (p_get_all * (1.0 - p_block_prop_success)) :
            (blobs_downloaded' = TOTAL_BLOBS) & (block_arrived' = 0) &
            (stage' = 3) & (timer_tick' = COST_RPC_RTT) & (step' = 1) +

        // 3. Partial/Tiny/Stall -> RPC
        (p_get_partial) : 
            (blobs_downloaded' = max(blobs_downloaded, 4)) & 
            (fail_count' = 0) &
            (stage' = 3) & (timer_tick' = COST_RPC_RTT) & (step' = 1) +            
        (p_get_tiny) : 
            (blobs_downloaded' = max(blobs_downloaded, 1)) & 
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + 1)) &
            (stage' = 3) & (timer_tick' = COST_RPC_RTT) & (step' = 1) +
        (p_stalled_fail) :
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + gossip_pruning_penalty)) &
            (stage' = 3) & (timer_tick' = COST_RPC_RTT) & (step' = 1);

    // ---------------------------------------------------------------------
    // [Stage 3: RPC Fallback]
    // ---------------------------------------------------------------------

    [] (is_running) & (stage=3) & (step=0) & (timer_tick = 0) ->
        // RPC Success
        p_rpc_success :
            (blobs_downloaded' = TOTAL_BLOBS) & (block_arrived' = 1) & (fail_count' = 0) &
            (stage' = 2) & (step' = 1) +
        // RPC Fail -> Retry
        (1.0 - p_rpc_success) :
            (fail_count' = min(MAX_FAIL_TOLERANCE, fail_count + gossip_pruning_penalty)) & 
            (stage' = 0) &
            (timer_tick' = COST_RETRY_DELAY) & 
            (step' = 1);

    // ---------------------------------------------------------------------
    // [Global Actions & Environment]
    // ---------------------------------------------------------------------
    
    // [Slot Penalty / Hard Reset Mechanism]
    // Triggered when fail_count reaches limit (Slot completely missed)
    [] (is_running) & (stage=0) & (step=0) & (timer_tick=0) & (need_switch) ->
        1.0 :
            (timer_tick' = SLOT_PENALTY) & 
            (stage' = 0) &
            (fail_count' = 0) &
            (retry_count' = 0) &           
            (blobs_downloaded' = 0) &     
            (block_arrived' = 0) &         
            (step' = 1);
            
    // [Safety Check]
    [] (is_running) & (stage=0) & (step=0) & (timer_tick=0) & (blobs_downloaded >= TOTAL_BLOBS) ->
        1.0 : (stage' = 2) & (step' = 1);

    // [Step 1: Environment Update]
    // Feedback loop: Network state adapts based on load history
    [] (is_running) & (step=1) ->
        // Spike
        p_endo_spike : (step'=0) & 
            (network_load' = min(MAX_NETWORK_LOAD, network_load + 1)) & 
            (net_state' = (min(MAX_NETWORK_LOAD, network_load + 1) >= HIGH_USAGE_THRES) ? 1 : net_state) +
        // Ease
        p_endo_ease : (step'=0) & 
            (network_load' = max(0, network_load - 1)) & 
            (net_state' = ((max(0, network_load - 1) >= HIGH_USAGE_THRES) ? 1 : 0)) +
        // Stay
        p_endo_stay : (step'=0) & 
            (network_load' = network_load) & 
            (net_state' = (is_high_usage ? 1 : 0));

    // [Sink State]
    [] (!is_running) -> 1.0 : (stage' = stage) & (step' = 0);

endmodule

// =========================================================================
// [6] Rewards
// =========================================================================

rewards "bandwidth_usage"
    // [A] Background Signaling
    (is_running) & (step=0) & (timer_tick > 0) : 
        (DISCOVERY_OVERHEAD_KB * meta_storm_factor * saturation_penalty) / GOSSIP_PROP_TICKS;
    // [B] Data Transmission
    [] (stage=1) & (step=0) & (timer_tick=0) :
        (
            (p_get_all * rem_blobs * BLOB_SIZE_KB * dynamic_amp_factor) +
            (p_get_partial * rem_blobs * BLOB_SIZE_KB * 0.80 * dynamic_amp_factor) +
            (p_get_tiny * rem_blobs * BLOB_SIZE_KB * 0.20 * dynamic_amp_factor) +
            (p_stalled_fail * rem_blobs * BLOB_SIZE_KB * 0.05 * dynamic_amp_factor)
        );
    // [C] RPC Repair
    [] (stage=3) & (step=0) & (timer_tick=0) :
        (rem_blobs * BLOB_SIZE_KB * 1.1); 
endrewards

rewards "latency_rtts"
    // Physical time
    (is_running) & (step=0) & (timer_tick > 0) : 1;    
    //  Congestion Soft Delay
    (is_running) & (step=0) & (timer_tick > 0) & (network_load > 2) : 
        (network_load - 2) * 0.3;      
    // Final Validation
    [] (stage=2) & (step=0) : latency_cost_old;
endrewards

rewards "compute_cost"
    // Gossip Path Validation
   [] (stage=1) & (step=0) & (timer_tick=0) & (block_arrived=1) : 
        rem_blobs * COMPUTE_WEIGHT_BLOB * saturation_penalty;
    // RPC Repair Validation
    [] (stage=3) & (step=0) & (timer_tick=0) : 
        rem_blobs * COMPUTE_WEIGHT_BLOB;
endrewards

// Success Condition
label "success" = (stage=2) & (step=0);