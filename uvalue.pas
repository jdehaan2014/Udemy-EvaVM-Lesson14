unit uValue;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$ModeSwitch implicitfunctionspecialization}

interface

uses
  SysUtils, Classes, uArray, Generics.Collections;

type
  TValueTyp = (
    vtNumber,
    vtBoolean,
    vtObject
  );

  TObjTyp = (
    otString,
    otCode
  );

  TObj = class
    Typ: TObjTyp;
    constructor Create(const ATyp: TObjTyp);
  end;

  PValue = ^TValue;
  TValue = record
    case Typ: TValueTyp of
      vtNumber:  (Number: Double);
      vtBoolean: (Bool: Boolean);
      vtObject:  (Obj: TObj);
  end;

  TValues = specialize TArrayList<TValue>;

  TStringObj = class(TObj)
    Data: String;
    constructor Create(const AData: String);
    function toString: String; override;
  end;

  TLocalVar = record
    Name: ShortString;
    ScopeLevel: Integer;
    constructor Create(AName: ShortString; AScopeLevel: Integer);
  end;

  //TLocals =specialize TArrayList<TLocalVar>;
  TLocals =specialize TList<TLocalVar>;

  TCodeObj = class(TObj)
    // Name of the unit, usually a function name
    Name: String;
    // Constant pool
    Constants: TValues;
    // Byte code
    Code: TCode;
    // current scope level
    ScopeLevel: Integer;
    // Local variables and functions
    Locals: TLocals;
    constructor Create(const AName: String);
    destructor Destroy; override;
    function toString: String; override;
    procedure addLocal(const AName: ShortString);
    function getLocalIndex(const AName: ShortString): Integer;
  end;


  function asObject(Value: TValue): TObj; inline;
  function isObject(Value: TValue): Boolean; inline;
  function isObjectTyp(Value: TValue; const Typ: TObjTyp): Boolean; inline;

  function NumVal(Value: Double): TValue; inline;
  function asNum(Value: TValue): Double; inline;
  function isNum(Value: TValue): Boolean; inline;

  function BoolVal(Value: Boolean): TValue; inline;
  function asBool(Value: TValue): Boolean; inline;
  function isBool(Value: TValue): Boolean; inline;

  function AllocString(const Value: String): TValue;
  function asString(Value: TValue): TStringObj; inline;
  function asPasString(Value: TValue): String; inline;
  function isString(Value: TValue): Boolean; inline;

  function AllocCode(const Name: String): TValue;
  function asCode(Value: TValue): TCodeObj; inline;
  function isCode(Value: TValue): Boolean; inline;

  function ValueToString(Value: TValue): String;

implementation

function asObject(Value: TValue): TObj; inline;
begin
  Result := Value.Obj;
end;

function isObject(Value: TValue): Boolean; inline;
begin
  Result := Value.Typ = vtObject;
end;

function isObjectTyp(Value: TValue; const Typ: TObjTyp): Boolean;
begin
  Result := isObject(Value) and (asObject(Value).Typ = Typ);
end;

function NumVal(Value: Double): TValue; inline;
begin
  Result.Typ := vtNumber;
  Result.Number := Value;
end;

function asNum(Value: TValue): Double;
begin
  Result := Value.Number;
end;

function isNum(Value: TValue): Boolean;
begin
  Result := Value.Typ = vtNumber;
end;

function BoolVal(Value: Boolean): TValue;
begin
  Result.Typ := vtBoolean;
  Result.Bool := Value;
end;

function asBool(Value: TValue): Boolean;
begin
  Result := Value.Bool;
end;

function isBool(Value: TValue): Boolean;
begin
  Result := Value.Typ = vtBoolean;
end;

function AllocString(const Value: String): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := TObj(TStringObj.Create(Value));
end;

function asString(Value: TValue): TStringObj;
begin
  Result := TStringObj(Value.Obj);
end;

function asPasString(Value: TValue): String;
begin
  Result := AsString(Value).Data;
end;

function isString(Value: TValue): Boolean;
begin
  Result := isObjectTyp(Value, otString);
end;

function AllocCode(const Name: String): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := TObj(TCodeObj.Create(Name));
end;

function asCode(Value: TValue): TCodeObj;
begin
  Result := TCodeObj(Value.Obj);
end;

function isCode(Value: TValue): Boolean;
begin
  Result := isObjectTyp(Value, otCode);
end;

function ValueToString(Value: TValue): String;
begin
  case Value.Typ of
    vtNumber: Result := Value.Number.ToString;
    vtBoolean: Result := IfThen(Value.Bool, 'true', 'false');
    vtObject: Result := Value.Obj.ToString;
  end;
end;

{ TObj }

constructor TObj.Create(const ATyp: TObjTyp);
begin
  Typ := ATyp;
end;

{ TStringObj }

constructor TStringObj.Create(const AData: String);
begin
  inherited Create(otString);
  Data := AData;
end;

function TStringObj.toString: String;
begin
  Result := '"' + Data + '"';
end;

{ TLocalVar }

constructor TLocalVar.Create(AName: ShortString; AScopeLevel: Integer);
begin
  Name := AName;
  ScopeLevel := AScopeLevel;
end;

{ TCodeObj }

constructor TCodeObj.Create(const AName: String);
begin
  inherited Create(otCode);
  Name := AName;
  ScopeLevel := 0;
  Locals := TLocals.Create;
end;

destructor TCodeObj.Destroy;
begin
  Code.Clear;
  Constants.Clear;
  Locals.Free;
  inherited Destroy;
end;

function TCodeObj.toString: String;
begin
  Result := '<Code ' + Name + '>';
end;

procedure TCodeObj.addLocal(const AName: ShortString);
begin
  Locals.Add(TLocalVar.Create(AName, ScopeLevel));
end;

function TCodeObj.getLocalIndex(const AName: ShortString): Integer;
var
  i: Integer;
begin
  if Locals.Count > 0 then
    for i := Locals.Count - 1 downto 0 do
      if Locals[i].Name = AName then
        Exit(i);

  Result := -1;
end;


end.

