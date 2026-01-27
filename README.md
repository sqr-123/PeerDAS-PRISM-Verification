# PeerDAS-PRISM-Verification
Formal verification models for the PeerDAS protocol using PRISM.

This repository describes the formal analysis of the Ethereum PeerDAS protocol as described in the paper "Cross-Layer Formal Analysis of Ethereum PeerDAS Protocol via Probabilistic Model Checking"using the probabilistic model checking tool "PRISM".

Three models are described:

 [1_Baseline_EIP4844.pm](1_Baseline_EIP4844.pm) model describing the EIP-4844 baseline protocol, focusing on blob propagation via GossipSub and RPC fallback mechanisms.
 [2_Proposed_PeerDAS.pm](2_Proposed_PeerDAS.pm) model describing the proposed PeerDAS protocol (EIP-7594) in an honest environment, featuring dynamic sampling windows and custody requirements.
 [3_Adversarial_Defense.pm](3_Adversarial_Defense.pm) model describing the PeerDAS protocol under adversarial conditions, simulating Eclipse and Sybil attacks along with a defense mechanism.

# Running models in PRISM

1.  Download and install PRISM: https://www.prismmodelchecker.org/download.php
2.  Open a model in the PRISM GUI.
3.  Navigate to the "Properties" tab.
4.  Verify or experiment with properties
5.  For more information on using the PRISM tool please refer to the [PRISM manual](https://www.prismmodelchecker.org/manual/).
