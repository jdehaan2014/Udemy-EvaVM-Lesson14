program gear;

{$mode objfpc}{$H+}

uses
  uVM, uValue, uLogger, uGlobals;

var
  Global: PGlobal;
  VM: TEvaVM;
  Result: TValue;
begin
  New(Global);
  Global^.Init;
  VM := TEvaVM.Create(Global);
  Result := VM.Exec(
    '(var x 5)' +
    '(set x (+ x 10)) ' +
    'x' +
    '(begin' +
    '  (var z 100)' +
    '  (set x 1000)' +
    '    (begin' +
    '      (var x 200)' +
    '     x)' +
    '  x)' +
    'x'
  );
  Log(Result);
  Writeln('All done.');
  Global^.Free;
  Dispose(Global);
end.

