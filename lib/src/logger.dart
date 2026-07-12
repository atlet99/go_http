/// Function used to emit log lines.
///
/// Defaults to [print] when not provided, allowing applications to redirect
/// output (e.g. to a file or a structured logger) without subclassing.
typedef Logger = void Function(Object? value);

/// Default logger: prints to the console.
void defaultLog(Object? value) => print(value);
