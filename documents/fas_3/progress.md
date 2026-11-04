# Fas 3 – Möten från .ics-filer

**Status:** Klart i koden (2026-11-04). Inte provkört med riktiga filer eller för hand i appen.
**Plan:** byggplanens steg 5a. Inloggning med Microsoft och Outlook-kalendern (steg 5b) är uppskjutna.

## Vad som är byggt

- **Fältet i verktygsfältet** visar mötet, t.ex. "Veckomöte · 4 nov. 2026 10:00". Utan möte står det "Lägg till möte (.ics)".
- **En `.ics`-fil** läggs till genom att man drar den till fältet, eller klickar på fältet och väljer **Välj .ics-fil…**.
- **Formuläret i popovern** visar uppgifterna, sparar ändringar direkt och har knappen **Rensa**.
- **Uppgifterna sparas på anteckningen,** i filens `meeting:`-block.
- **✨ Skapa protokoll** använder mötet direkt. Saknas mötestitel öppnas popovern i stället.

## Filer

| Del | Filer |
|---|---|
| Läsa `.ics` | `Domain/ICSParser.swift` |
| Datamodell | `Domain/MeetingDetails.swift`, `Domain/Note.swift`, `Domain/FrontMatter.swift` |
| Gränssnitt | `UI/Meeting/` (`MeetingToolbarField`, `MeetingDetailsForm`, `MeetingImportModel`) |
| Protokoll | `UI/Protocol/GenerateProtocolSheet.swift`, `UI/Protocol/ProtocolGenerationModel.swift` |

## Beslut

- **Egen parser utan beroenden.** Bara det appen behöver läses.
- **`MeetingReference` är borttagen.** `Note.meeting` är nu en `MeetingDetails`, och `eventID` är `nil` tills Outlook kopplas in. Protokoll som redan skapats med `eventId: ""` läses in som vanligt.
- **Deltagare som tackat nej och rum tas inte med.** Annars kan de hamna som närvarande i protokollet.
- **Teams-blocket tas bort** från beskrivningen, så att länk och lösenkod inte skickas till AI-tjänsten.
- **Windows-tidszoner** översätts med en tabell över vanliga zoner i `ICSParser`. Okänd tidszon läses som lokal tid och ger en varning.
- **Heldagsmöten** får ingen sluttid.
- **Återkommande möten:** filen anger det första tillfället, så en uppmaning visas att kontrollera datumet.
- **En anteckning med bara ett möte behålls.** `Note.hasContent` räknar in mötet.
- **Filnamnet och titeln i listan** tar mötets titel om anteckningen saknar text.

## Verifiering

85 tester går igenom. De täcker:
- `ICSParser`: Outlook-fil med Windows-tidszon och Teams-text, Kalender-fil, radfortsättningar, citerade parametrar, heldag, `DURATION`, okänd tidszon, återkommande och flera möten, ogiltig och för stor fil
- front matter med alla mötesfält, och det äldre formatet
- import av fil, val mellan flera möten och fil som inte går att läsa
- att en anteckning med bara ett möte behålls

## Kvar att göra

- **Provkör med riktiga filer** från Outlook och Kalender. Exempelfilerna i testerna är skrivna för hand utifrån formatet.
- **Kontrollera fältet för hand:** utseende, popover och dra och släpp. Claude kan inte ta skärmbilder här, och att släppa filer i verktygsfältet har inte provats.
- **Promptinjektion:** beskrivningen i en `.ics`-fil kommer ofta från någon annan och skickas till AI-tjänsten. Effekten är begränsad, eftersom svaret bara blir en ny anteckning.
