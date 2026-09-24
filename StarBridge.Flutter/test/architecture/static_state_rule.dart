/// Detect field declarations, not expression-bodied getters (`=>`).
bool hasMutableStaticField(String source) => RegExp(
  r'^\s*static\s+(?!const\b|final\b)(?:late\s+)?[\w<>,? ]+\s+\w+\s*(?:=(?!>)|;)',
  multiLine: true,
).hasMatch(source);
