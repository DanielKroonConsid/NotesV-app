# Uppgifter i NotesV

Uppgifter samlar det som ska göras efter dina möten på ett ställe. Du hittar vyn under **Uppgifter** i sidopanelen.

Appen letar efter nya punkter i dina mötesprotokoll, men inget läggs till i listan förrän du har granskat det. Du kan också skapa egna uppgifter som inte hör till något protokoll.

## Kom igång

1. Öppna **NotesV → Inställningar → Allmänt**.
2. Skriv namnen du brukar stå under i protokoll, med komma emellan, till exempel `Ada Ek, Ada`.

Namnen används bara för att välja **Jag** i förväg när du granskar nya uppgifter. De sparas på den här Macen. Du kan använda Uppgifter utan dem, men då väljer du **Jag** själv.

## Lägga till uppgifter från protokoll

Appen går igenom alla mötesprotokoll, även skickade, och letar efter checkboxar som inte är bockade. Det sker lokalt, och inget skickas till någon AI-tjänst.

Finns det något nytt visas en siffra vid **Uppgifter** i sidopanelen och en knapp högst upp i listan, till exempel **3 nya uppgifter**. När du klickar på knappen öppnas **Nya uppgifter**, med punkterna grupperade per möte.

Appen fyller i det den kan läsa från raden, som i protokollet har formen `uppgift – ansvarig, datum`. Kontrollera och ändra det som behövs:

- **Uppgift:** texten som visas i listan.
- **Ansvarig:** skriv ett namn, eller välj **Jag**, en person från mötet eller **Ingen ansvarig** med personikonen.
- **Förfallodatum:** slå på rutan och välj ett datum.
- **Backlogg:** lägg uppgiften bland framtida uppgifter, utan datum.
- **Notering** och **Underuppgifter:** se nedan.

Sedan väljer du vad som ska hända med varje rad:

| Du vill | Gör så här |
|---|---|
| Lägga till raden | Låt rutan till vänster vara ibockad och välj **Lägg till** |
| Bestämma senare | Bocka ur rutan. Raden kommer tillbaka nästa gång |
| Aldrig se raden igen | Klicka på **✕** (Ignorera) |

Checkboxar som redan är bockade i protokollet räknas som klara och föreslås inte.

### Datum som appen förstår

Relativa datum räknas från mötets datum.

| I protokollet | Tolkas som |
|---|---|
| `2026-11-20`, `20/11`, `20 november`, `Nov 20` | Det datumet. Utan år väljs närmaste datum från mötet och framåt |
| `idag`, `imorgon`, `today`, `tomorrow` | Mötesdagen eller dagen efter |
| `fredag`, `Friday` | Nästa fredag efter mötet |
| `v. 46`, `vecka 46`, `week 46`, `nästa vecka`, `next week` | Veckans fredag |

Allt annat, till exempel "innan jul", gissas inte. Datumet lämnas tomt, och protokollets text visas i granskningen så att du kan välja själv. `20/11` läses alltid som dag/månad.

## Skapa en egen uppgift

Klicka på **+** i verktygsraden. **Jag** är förvalt som ansvarig. Uppgiften märks **Manuell uppgift** i listan och har inget protokoll, så högerkolumnen är tom när du klickar på den.

## Översikten

### Flikar

| Flik | Visar |
|---|---|
| **Mina** | Öppna uppgifter där du är ansvarig |
| **Andras** | Öppna uppgifter med en annan ansvarig eller utan ansvarig |
| **Alla** | Mina och Andras tillsammans |
| **Backlogg** | Framtida uppgifter, både dina och andras |
| **Avklarade** | Alla avbockade uppgifter |

### Sortering

Knappen med pilarna i verktygsraden sorterar listan:

- **Förfallodatum:** delar in listan i Försenade, Idag, Denna vecka, Senare och Utan datum.
- **Möte:** samlar uppgifterna per möte, med det senaste först. Manuella uppgifter ligger sist.
- **Ansvarig:** visar dig först, sedan övriga i bokstavsordning och sist uppgifter utan ansvarig.

Sökfältet filtrerar den valda fliken. Det söker i uppgiften, ansvarig, mötets namn, noteringen och underuppgifterna.

### Arbeta med en uppgift

| Du vill | Gör så här |
|---|---|
| Se protokollet | Klicka en gång på uppgiften. Det visas i högerkolumnen |
| Ändra uppgiften | Dubbelklicka, eller högerklicka och välj **Ändra…** |
| Öppna protokollet i eget fönster | Högerklicka och välj **Öppna protokollet i eget fönster** |
| Flytta till eller från backloggen | Högerklicka, eller ändra **Backlogg** i rutan |
| Bocka av | Klicka på checkboxen |
| Ta bort | Högerklicka, välj **Ta bort från listan** och bekräfta med **OK** |

## Avklarade uppgifter

En avbockad uppgift flyttas till **Avklarade**. Tar du bort bocken går den tillbaka till sin flik, även till **Backlogg** om den låg där.

För protokolluppgifter följer bocken checkboxen i protokollet åt båda håll. Bockar du av i listan bockas raden i protokollet, och tvärtom. Har raden tagits bort från protokollet gäller uppgiftens egen status.

## Backlogg

Backloggen är för uppgifter du vill göra någon gång, men som inte har något datum än.

**Datumet tas bort** när en uppgift flyttas till backloggen, och det kommer inte tillbaka när du flyttar ut den. Då sätter du ett nytt datum med **Ändra…**.

## Noteringar och underuppgifter

**Notering** är en vanlig text för dig själv, till exempel vad du väntar på. Första raden visas i listan, och hela noteringen visas när du håller pekaren över uppgiften.

**Underuppgifter** delar upp en uppgift i steg. Du lägger till och tar bort dem i **Ändra…**. I listan ligger de under uppgiften, kan bockas av direkt där och räknas ihop, till exempel `1/3`.

Uppgiften och underuppgifterna bockas av var för sig. Uppgiften blir inte avklarad när alla steg är klara, utan det bestämmer du själv.

## Ta bort och ignorera

- **Protokolluppgift:** försvinner från listan. Checkboxen finns kvar i protokollet men föreslås inte igen.
- **Manuell uppgift:** raderas helt och går inte att få tillbaka.
- **Raderat protokoll:** dess uppgifter försvinner från översikten och kommer tillbaka om protokollet återställs.

## Var uppgifterna sparas

Uppgifterna ligger i samma Markdown-filer som övriga anteckningar, så de följer med vid synk och när du byter lagringsmapp.

- **Protokolluppgifter** sparas i fältet `tasks` i protokollets front matter.
- **Manuella uppgifter** sparas i `Manual Tasks/Tasks.md`. Mappen visas inte i sidopanelen.

```yaml
tasks:
  - source: "Skicka offert – Ada Ek, fredag"
    task: "Skicka offert"
    owner: "Ada Ek"
    mine: false
    due: 2026-11-20
    note: "Väntar på pris från Bo."
    subtasks: ["[x] Hämta pris", "[ ] Skriv utkast"]
    status: open
```

`source` är originalraden i protokollet. Det är så appen vet att en checkbox redan är behandlad. `status` är `open`, `done` eller `ignored`, och en uppgift i backloggen har även `backlog: true`.

Inget av detta hamnar i protokollets text. Noteringar och underuppgifter följer inte med **Copy for Email** och skickas inte till AI-tjänsten. Ligger filerna i en synkad mapp följer de däremot med dit.

## Bra att veta

- **Texten i protokollet ändras inte** när du ändrar en uppgift. Protokollet kan vara utskickat, och uppgiften är din egen uppföljning.
- **Ändrar du en checkbox text i protokollet** föreslås den som en ny punkt. Den gamla uppgiften ligger kvar tills du tar bort den.
- **Flera ansvariga med komma emellan**, till exempel `Ada, Bo, 20 nov`, tolkas fel i förifyllningen. Skriv `Ada och Bo` eller rätta i granskningen.
- **Äldre versioner av NotesV** känner inte till uppgifterna. Sparar version 0.1.1 från GitHub ett protokoll tas dess uppgifter bort från filen, så använd inte den versionen på samma mapp.
- **Påminnelser** finns inte. Appen meddelar dig inte när något förfaller.
