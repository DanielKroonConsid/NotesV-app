# NotesV – byggplan

**Datum:** 2026-10-23
**Status:** Planering klar. Inget är byggt än.
**Miljö:** Xcode 26.5, appen ska stödja macOS 15 Sequoia och senare.

Projektets krav finns i [`CLAUDE.md`](../../CLAUDE.md). Det här dokumentet beskriver i vilken ordning vi bygger appen.

## Princip

Vi börjar med de delar som går att bygga och testa helt lokalt. Delarna som kräver Microsoft 365 kommer sist, eftersom de behöver förberedelser utanför koden (appregistrering och licenser).

Lagring och AI ligger bakom egna gränssnitt (`StorageService` och `ProtocolGenerator`). Därför kan lokal lagring bytas mot OneDrive, och OpenAI kompletteras med Copilot, utan att resten av appen ändras.

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
- Tills kalendern är kopplad skrivs mötesuppgifterna in för hand.

**Klart när:** hela flödet från mötespunkter till färdigt protokoll fungerar.

## Fas 3: Microsoft 365

### Steg 5 – Inloggning och kalender
- Inloggning med Microsoft (MSAL) som fungerar för alla organisationer.
- En vy där man väljer ett möte från Outlook-kalendern, med rubrik, tid, organisatör, deltagare och agenda.

**Klart när:** ett valt möte fyller automatiskt i mötesuppgifterna i protokollet.

### Steg 6 – OneDrive
- Man väljer en mapp i OneDrive i inställningarna.
- Appen synkar anteckningarna mot den mappen och har en lokal kopia för när man är offline.
- Appen märker om någon har ändrat en fil utanför appen, i stället för att skriva över ändringen.

**Klart när:** anteckningar sparas i den valda OneDrive-mappen och går att öppna även offline.

### Steg 7 – Copilot
- Först kontrollerar vi om det finns ett API för den Copilot som ingår i vanliga M365-abonnemang som Business Basic.
- Om det finns bygger vi `CopilotProtocolGenerator`. Om det kräver den betalda Microsoft 365 Copilot-licensen bestämmer vi tillsammans hur vi gör.

**Klart när:** Copilot fungerar som AI-tjänst, eller det finns ett beslut om alternativet.

## Förberedelser utanför koden

| Inför steg | Vad | Vem |
|---|---|---|
| 4 | En API-nyckel från OpenAI. Den skrivs in i appen, aldrig i chatten eller i koden. | Daniel |
| 5 | En appregistrering i Microsoft Entra (Azure-portalen) som fungerar för alla organisationer, med behörigheterna `User.Read`, `Calendars.Read` och `Files.ReadWrite`. Claude kan skriva en steg-för-steg-guide. | Daniel, med guide från Claude |
| 7 | Svaret från kontrollen om Copilot-API:t. | Claude kontrollerar, Daniel beslutar |
