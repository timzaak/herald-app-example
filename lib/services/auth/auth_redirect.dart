String safeAuthDestination(String? value) {
  if (value == null || value.isEmpty || !value.startsWith('/')) {
    return '/index';
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      value.startsWith('//')) {
    return '/index';
  }
  return uri.toString();
}
