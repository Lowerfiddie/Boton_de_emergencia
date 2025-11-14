const String kRolAlumnoEstandar = 'Alumno/a';

String normalizeRole(String? role) {
  return (role ?? '').trim().toLowerCase();
}

bool isAlumnoRole(String? role) {
  final normalized = normalizeRole(role);
  return normalized == 'alumno/a' ||
      normalized == 'alumno' ||
      normalized == 'alumna' ||
      normalized == 'estudiante';
}

const Set<String> _monitoringRoles = <String>{
  'docente',
  'madre/padre/tutor',
  'padre/madre/tutor',
  'padre/madre/tutora',
  'madre/padre/tutora',
  'tutor',
  'tutora',
  'padre',
  'madre',
  'vecino',
  'vecina',
  'vecino/a',
};

bool isMonitoringRole(String? role) {
  final normalized = normalizeRole(role);
  return _monitoringRoles.contains(normalized);
}
