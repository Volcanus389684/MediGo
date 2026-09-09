class Medication {
  const Medication({
    required this.name,
    required this.strength,
    required this.position,
    required this.available,
    required this.stock,
    this.requiresPrescription = true,
    this.imageUrl,
    this.instructions = 'Take as directed.',
  });

  final String name;
  final String strength;
  final String position;
  final bool available;
  final int stock;
  final bool requiresPrescription;
  final String? imageUrl;
  final String instructions;
}

class PatientData {
  const PatientData({
    required this.name,
    required this.age,
    required this.weight,
    required this.hasPrescription,
  });

  final String name;
  final int age;
  final double weight;
  final bool hasPrescription;
}
