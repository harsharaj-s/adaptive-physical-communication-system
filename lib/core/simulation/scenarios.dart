import 'package:adaptive_physical_communication/core/simulation/simulated_medium.dart';
import 'package:adaptive_physical_communication/core/simulation/simulation_orchestrator.dart';

class ScenarioDefinition {
  const ScenarioDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.dataSize,
    required this.createPair,
  });

  final String id;
  final String name;
  final String description;
  final int dataSize;
  final SimulationPair Function() createPair;
}

final scenarios = <ScenarioDefinition>[
  ScenarioDefinition(
    id: 'optical-always-good',
    name: 'Optical Always Good',
    description: 'Optical channel maintains high quality throughout transfer.',
    dataSize: 4096,
    createPair: () => createSimulationPair(
      opticalProfileA: const ChannelSimulationProfile(
        packetLossRate: 0.005,
        baseThroughput: 20000,
      ),
      opticalProfileB: const ChannelSimulationProfile(
        packetLossRate: 0.005,
        baseThroughput: 20000,
      ),
      acousticProfileA: const ChannelSimulationProfile(packetLossRate: 0.05),
      acousticProfileB: const ChannelSimulationProfile(packetLossRate: 0.05),
    ),
  ),
  ScenarioDefinition(
    id: 'acoustic-always-good',
    name: 'Acoustic Always Good',
    description: 'Optical unavailable; acoustic channel selected and stable.',
    dataSize: 4096,
    createPair: () => createSimulationPair(
      opticalProfileA: const ChannelSimulationProfile(discoverable: false),
      opticalProfileB: const ChannelSimulationProfile(discoverable: false),
      acousticProfileA: const ChannelSimulationProfile(
        packetLossRate: 0.02,
        baseThroughput: 10000,
      ),
      acousticProfileB: const ChannelSimulationProfile(
        packetLossRate: 0.02,
        baseThroughput: 10000,
      ),
    ),
  ),
  ScenarioDefinition(
    id: 'optical-degrades',
    name: 'Optical Starts Good, Becomes Poor',
    description:
        'Optical selected initially, degrades mid-transfer, may switch to acoustic.',
    dataSize: 8192,
    createPair: () => createSimulationPair(
      acousticProfileA: const ChannelSimulationProfile(
        packetLossRate: 0.03,
        baseThroughput: 9000,
        confidence: 0.8,
      ),
      acousticProfileB: const ChannelSimulationProfile(
        packetLossRate: 0.03,
        baseThroughput: 9000,
      ),
      opticalDegradation: DegradationSchedule(
        afterPacket: 15,
        profile: const ChannelSimulationProfile(
          baseThroughput: 2000,
          packetLossRate: 0.30,
          baseLatencyMs: 500,
          confidence: 0.3,
          stability: 0.2,
        ),
      ),
    ),
  ),
  ScenarioDefinition(
    id: 'random-loss',
    name: 'Random Packet Loss',
    description: 'Moderate random packet loss on optical channel.',
    dataSize: 4096,
    createPair: () => createSimulationPair(
      opticalProfileA: const ChannelSimulationProfile(
        packetLossRate: 0.08,
        corruptionRate: 0.02,
      ),
      opticalProfileB: const ChannelSimulationProfile(packetLossRate: 0.08),
      acousticProfileA: const ChannelSimulationProfile(packetLossRate: 0.06),
      acousticProfileB: const ChannelSimulationProfile(packetLossRate: 0.06),
    ),
  ),
  ScenarioDefinition(
    id: 'burst-loss',
    name: 'Burst Packet Loss',
    description: 'Optical experiences burst loss mid-transfer.',
    dataSize: 6144,
    createPair: () => createSimulationPair(
      opticalDegradation: DegradationSchedule(
        afterPacket: 8,
        profile: const ChannelSimulationProfile(
          packetLossRate: 0.45,
          baseThroughput: 4000,
          baseLatencyMs: 300,
        ),
      ),
    ),
  ),
  ScenarioDefinition(
    id: 'both-degrade',
    name: 'Both Channels Degrade',
    description: 'Both optical and acoustic degrade during transfer.',
    dataSize: 2048,
    createPair: () => createSimulationPair(
      opticalDegradation: DegradationSchedule(
        afterPacket: 10,
        profile: const ChannelSimulationProfile(
          packetLossRate: 0.25,
          baseThroughput: 3000,
        ),
      ),
      acousticDegradation: DegradationSchedule(
        afterPacket: 10,
        profile: const ChannelSimulationProfile(
          packetLossRate: 0.20,
          baseThroughput: 4000,
        ),
      ),
    ),
  ),
  ScenarioDefinition(
    id: 'acoustic-recovers',
    name: 'Acoustic Starts Poor, Recovers',
    description: 'Acoustic channel recovers mid-transfer.',
    dataSize: 4096,
    createPair: () => createSimulationPair(
      opticalProfileA: const ChannelSimulationProfile(discoverable: false),
      opticalProfileB: const ChannelSimulationProfile(discoverable: false),
      acousticProfileA: const ChannelSimulationProfile(
        packetLossRate: 0.15,
        baseThroughput: 3000,
        confidence: 0.4,
      ),
      acousticProfileB: const ChannelSimulationProfile(
        packetLossRate: 0.15,
        baseThroughput: 3000,
      ),
      acousticRecovery: DegradationSchedule(
        afterPacket: 30,
        profile: const ChannelSimulationProfile(
          packetLossRate: 0.02,
          baseThroughput: 10000,
          confidence: 0.85,
        ),
      ),
    ),
  ),
  ScenarioDefinition(
    id: 'repeated-degradation',
    name: 'Repeated Degradation and Recovery',
    description: 'Optical degrades and recovers during transfer.',
    dataSize: 10240,
    createPair: () => createSimulationPair(
      acousticProfileA: const ChannelSimulationProfile(
        packetLossRate: 0.05,
        baseThroughput: 8000,
      ),
      acousticProfileB: const ChannelSimulationProfile(
        packetLossRate: 0.05,
        baseThroughput: 8000,
      ),
      opticalDegradation: DegradationSchedule(
        afterPacket: 12,
        profile: const ChannelSimulationProfile(
          packetLossRate: 0.35,
          baseThroughput: 2500,
          confidence: 0.25,
        ),
      ),
      opticalRecovery: DegradationSchedule(
        afterPacket: 35,
        profile: const ChannelSimulationProfile(
          packetLossRate: 0.01,
          baseThroughput: 18000,
          confidence: 0.9,
        ),
      ),
    ),
  ),
  ScenarioDefinition(
    id: 'vibration-coupled',
    name: 'Vibration Coupled',
    description:
        'Optical and acoustic blocked; vibration channel selected via physical coupling.',
    dataSize: 2048,
    createPair: () => createSimulationPair(
      opticalProfileA: const ChannelSimulationProfile(discoverable: false),
      opticalProfileB: const ChannelSimulationProfile(discoverable: false),
      acousticProfileA: const ChannelSimulationProfile(discoverable: false),
      acousticProfileB: const ChannelSimulationProfile(discoverable: false),
      vibrationProfileA: const ChannelSimulationProfile(
        packetLossRate: 0.03,
        baseThroughput: 900,
        confidence: 0.82,
      ),
      vibrationProfileB: const ChannelSimulationProfile(
        packetLossRate: 0.03,
        baseThroughput: 900,
      ),
    ),
  ),
];

ScenarioDefinition? getScenario(String id) {
  try {
    return scenarios.firstWhere((s) => s.id == id);
  } catch (_) {
    return null;
  }
}
