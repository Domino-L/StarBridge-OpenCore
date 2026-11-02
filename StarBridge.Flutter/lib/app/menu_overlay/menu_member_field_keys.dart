const menuMemberFieldKeys = <String>{
  'hidden',
  'restricted',
  'notInGame',
  'notInServer',
  'waitingRecognition',
  'waitingServerSync',
  'locationPending',
  'lowConfidenceLocation',
};

String menuMemberFieldKey(Map value, String field) {
  if (!value.containsKey(field)) return '';
  final key = value[field];
  if (key is! String || key.isNotEmpty && !menuMemberFieldKeys.contains(key)) {
    throw const FormatException();
  }
  return key;
}
