unit uArray;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$ModeSwitch implicitfunctionspecialization}

interface

uses
  SysUtils;

type

  generic TArrayList<T> = record
    private type PT = ^T;
    private
      fItems: PT;
      fCount: Integer;
      fCapacity: Integer;
      function getItem(i: Integer): T;
      procedure setItem(i: Integer; AValue: T);
    public
      property Items[i:Integer]: T read getItem write setItem; default;
      property Data: PT read fItems write fItems;
      property Count: Integer read fCount write fCount;
      property Capacity: Integer read fCapacity write fCapacity;
      function Add(AValue: T): Integer;
      procedure AddRange(Values: array of T);
      procedure Init;
      procedure Clear;
  end;

  TCode = specialize TArrayList<Byte>;

implementation

{ TArrayList }

function TArrayList.getItem(i: Integer): T;
begin
  Result := fItems[i];
end;

procedure TArrayList.setItem(i: Integer; AValue: T);
begin
  fItems[i] := AValue;
end;

function TArrayList.Add(AValue: T): Integer;
begin
  if fCapacity < (fCount + 1) then
    begin
      fCapacity := IfThen(fCapacity < 16, 16, fCapacity * 2);

      // FPC heapmanager auto keeps track of old size.
      fItems := ReAllocMem(fItems, SizeOf(T)*fCapacity);
    end;

  fItems[fCount] := AValue;
  Result := fCount;
  Inc(fCount);
end;

procedure TArrayList.AddRange(Values: array of T);
var
  Value: T;
begin
  for Value in Values do
    Add(Value);
end;

procedure TArrayList.Init;
begin
  fItems := Nil;
  fCount := 0;
  fCapacity := 0;
end;

procedure TArrayList.Clear;
begin
  fItems := ReAllocMem(fItems, 0);
  Init;
end;

end.

