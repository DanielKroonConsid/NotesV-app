# NotesV – byggplan

**Datum:** 2026-10-23
**Status:** Steg 1–4, 5a och 6 är byggda. Reviderad 2026-11-05.
**Miljö:** Xcode 26.5, appen ska stödja macOS 15 Sequoia och senare.

Projektets krav finns i [`CLAUDE.md`](../../CLAUDE.md). Det här dokumentet beskriver i vilken ordning vi bygger appen.

**Ändrat 2026-11-04:** NotesV går inte att registrera i Microsoft Entra. Därför är inloggning, Outlook och Copilot strukna, och OneDrive kan inte kopplas in via Graph.

## Princip

Vi bygger delar som går att bygga och testa helt lokalt, utan koppling till Microsoft 365.

Lagring och AI ligger bakom egna gränssnitt (`StorageService` och `ProtocolGenerator`). Därför kan lagringsplatsen och AI-tjänsten bytas utan att resten av appen ändras.

## Fas 1: Grunden (helt lokalt)

### Steg 1 – Projektgrund
- Ett Xcode-projekt för macOS 15 med SwiftUI.
- Mapparna `UI/`, `Domain/` och `Services/`.
- En översättningsfil (`Localizable.xcstrings`) för svenska och engelska.
- Ett testmål med Swift Testing.
- En `.gitignore` för macOS- och Xcode-filer, så att bl.a. `.DS_Store` inte kommer med.

**Klart när:** appen bygger och startar, och testerna går att köra.

### Steg 2 – Datamodell och Markdown
- Modeller för anteckning, mapp och möte.
- `MarkdownCodec`, som översätter mellan formaterad text och Markdown (GitHub Flavored Markdown med YAML-huvud), enligt tabellen i `CLAUDE.md`.
- Tester som kontrollerar att inget går förlorat när text översätts fram och tillbaka.

**Klart när:** alla textstilar, listor, checklistor och tabeller klarar testerna fram och tillbaka.

### Steg 3 – Gränssnitt som i Notes
- Tre kolumner: mappar, anteckningslista och editor (`NavigationSplitView`).
- En editor byggd på `NSTextView` med stilarna Rubrik, Huvudrubrik, Underrubrik, Brödtext och Fast breddsteg, samt fet, kursiv, understruken och genomstruken text.
- Punktlistor, strecklistor, numrerade listor och checklistor.
- Tabeller, fästa anteckningar och sökning i all text.
- Samma kortkommandon som i Notes.
- Anteckningarna sparas som Markdown-filer på datorn via `StorageService`.

**Klart när:** det går att skapa, formatera, söka i och spara anteckningar som ser ut och beter sig som i Notes.

## Fas 2: AI

### Steg 4 – Inställningar och OpenAI
- Ett inställningsfönster där man väljer AI-tjänst och anger eller tar bort sin OpenAI-nyckel.
- Nyckeln sparas bara i Nyckelringen.
- Appen väljer automatiskt den senaste OpenAI-modellen, och man kan välja en annan modell i inställningarna.
- `OpenAIProtocolGenerator` skapar protokoll med de fem avsnitten: mötesinfo, deltagare, agenda och diskussion, beslut och åtgärdspunkter.

**Klart när:** hela flödet från mötespunkter till färdigt protokoll fungerar.

## Fas 3: Möten och lagring

### Steg 5a – Möten från .ics-filer (klart 2026-11-04)
- Fältet i verktygsfältet tar emot en `.ics`-fil, och uppgifterna sparas på anteckningen.
- Ett formulär rättar uppgifterna och täcker möten utan fil.
- Se [fas_3/progress.md](../fas_3/progress.md).

### Steg 5b – Inloggning och kalender (struket 2026-11-04)
Krävde en appregistrering i Microsoft Entra, som inte går att göra. Möten kommer från `.ics`-filer och formuläret.

### Steg 6 – Valfri lagringsmapp (klart 2026-11-05)
Den planerade kopplingen till OneDrive via Graph går inte att bygga utan appregistrering. I stället gäller:
- Man väljer en mapp på datorn i inställningarna, till exempel mappen som OneDrive-appen synkar.
- OneDrive-appen sköter synk och offline-kopia. NotesV sparar bara filerna i mappen.
- Appen märker om någon har ändrat en fil utanför appen, i stället för att skriva över ändringen.
- Appen behöver skrivbehörighet för mappen som användaren väljer och måste minnas mappen mellan starter.

**Klart när:** anteckningar sparas i den valda mappen och ändringar utanför appen skrivs inte över.

Se [fas_3/progress.md](../fas_3/progress.md).

### Steg 7 – Copilot (struket 2026-11-04)
Krävde användarens Microsoft-inloggning och därmed en appregistrering. OpenAI-kompatibla tjänster är den enda AI-vägen.

## Förberedelser utanför koden

| Inför steg | Vad | Vem |
|---|---|---|
| 4 | En API-nyckel från OpenAI. Den skrivs in i appen, aldrig i chatten eller i koden. | Daniel |
