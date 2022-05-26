unit uAST;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections;

type

  TExprTyp = (
    etNumber,
    etString,
    etSymbol,
    etList
  );

  TExpr = class;
  TListEntries = specialize TObjectList<TExpr>;

  TExpr = class
    Typ: TExprTyp;
    Num: Double;
    Str: String; // string or a symbol
    List: TListEntries;
    constructor Create(Value: Double);
    constructor Create(Value: String);
    constructor Create(Value: TListEntries);
    destructor Destroy; override;
    procedure Print;
  end;

implementation

{ TExpr }

constructor TExpr.Create(Value: Double);
begin
  Typ := etNumber;
  Num := Value;
end;

constructor TExpr.Create(Value: String);
begin
  if Value.StartsWith('"') then
    begin
      Typ := etString;
      Str := Value.DeQuotedString('"');
    end
  else
    begin
      Typ := etSymbol;
      Str := Value;
    end;
end;

constructor TExpr.Create(Value: TListEntries);
begin
  Typ := etList;
  List := Value;
end;

destructor TExpr.Destroy;
begin
  if Assigned(List) then List.Free;
  inherited Destroy;
end;

procedure TExpr.Print;
var
  Item: TExpr;
begin
  //Writeln('Expression');
  case Typ of
    etNumber: Write('  Number: ', Num.ToString);
    etString: Write('  String: ', Str);
    etSymbol: Write('  Symbol: ', Str);
    etList:
      begin
        Writeln('  List: (');
        for Item in List do
          Item.Print;
        Write('  )');
      end;
  end;
  Writeln;
end;

end.

