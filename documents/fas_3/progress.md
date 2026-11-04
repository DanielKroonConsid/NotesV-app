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

115 tester går igenom. De täcker:
- `ICSParser`: Outlook-fil med Windows-tidszon och Teams-text, Kalender-fil, radfortsättningar, citerade parametrar, heldag, `DURATION`, okänd tidszon, återkommande och flera möten, ogiltig och för stor fil
- front matter med alla mötesfält, och det äldre formatet
- import av fil, val mellan flera möten och fil som inte går att läsa
- att en anteckning med bara ett möte behålls

## Protokoll som bilaga (2026-11-04)

Arbetssättet är nu: skapa en anteckning, ge den en rubrik, skapa protokollet. Originalanteckningen ändras aldrig.

- **Protokollet sparas i mappen Mötesprotokoll** i sidofältet, som en egen anteckning. Mappen är en systemmapp och skapas med det första protokollet.
- **Kopplingen** sparas som `sourceNote` i protokollets fil.
- **Anteckningen visar sina bilagor** i en rad ovanför texten. Ett klick öppnar protokollet i ett eget fönster, så att det kan ligga bredvid anteckningen.
- **Ändringar sparas automatiskt,** som i andra anteckningar. Protokollet öppnas också direkt när det har skapats.
- **Från protokollet** går en knapp tillbaka till anteckningen när det visas i huvudfönstret.
- **Om samma anteckning är öppen i två fönster** uppdateras det andra fönstret direkt.
- **Radera ett protokoll:** högerklicka på bilagan, klicka på papperskorgen i protokollfönstret eller radera det i mappen Mötesprotokoll. Det flyttas till Nyligen raderade, som andra anteckningar, och går att radera permanent där.
- **Protokoll som flyttats till Nyligen raderade** visas inte som bilagor.
- **Protokoll skapade före den här ändringen** har ingen koppling och ligger kvar där de är.

## Justeringar efter provkörning (2026-11-04)

- **Luftigare text:** större radavstånd i alla anteckningar och mer luft kring rubriker, stycken och listor. Modellen ombeds också skriva korta stycken och hellre flera ämnen än ett långt.
- **Matcha ansvariga:** före att protokollet skapas visas en dialog med varje åtgärdspunkt. Ansvarig skrivs in eller väljs bland personerna i mötet, och datum är valfritt. Dialogen visas inte om protokollet saknar åtgärdspunkter.
- **Datum är valfritt:** saknas datum står inget alls, i stället för "[Datum saknas]". Saknad ansvarig får fortfarande en platshållare.
- **Begränsning:** dialogen finns bara när protokollet skapas. I ett färdigt protokoll ändrar man texten direkt.

## Kopiera till e-post (2026-11-04)

- **Knappen Kopiera för e-post** i protokollfönstret, och samma val när man högerklickar på bilagan, kopierar hela protokollet.
- **Vanlig kopiering (⌘C)** i editorn gör samma sak med det markerade.
- **Format:** HTML och RTF behåller rubriker, fetstil, listor och tabeller. Ren text är reserv. Allt byggs av `EmailFormatter` och `EmailClipboard`.
- **Punkter och kryssrutor** ritas av editorn och finns inte i texten, så de läggs till vid kopieringen. Checklistor blir ☐ och ☑.

## Klistra in från Apple Notes (2026-11-04)

- **Flytt av anteckningar:** kopiera i Apple Notes och klistra in med ⌘V i en ny anteckning. Formateringen behålls.
- **Hur det fungerar:** `RichPasteImporter` läser RTF eller HTML från urklipp. Rubriknivåer räknas ut från textstorlek i förhållande till brödtexten. Listor läses från listinformationen eller från tecken som •, 1. och ☐. Tabeller, fetstil, kursiv, understruken och genomstruken text följer med.
- **Andra program:** samma sak gäller text från till exempel webbsidor och Word.
- **Följer inte med:** bilder och bifogade filer. Text i länkar behålls, men inte adressen.
- **Tabellceller** tar emot ren text. Klistra in och matcha stil ger också ren text.
- **Provat med riktiga Apple Notes:** urklipp innehåller `public.rtf`, med titel i 20 punkter och brödtext i 13. Rubriker och strecklistor tolkas rätt. Checklistor är ännu inte kontrollerade.
- **Rättat fel:** all inklistrad text blev stor i nya anteckningar, eftersom `insertText` lade titeltypsnittet på allt. Texten sätts nu in direkt i textlagringen och går fortfarande att ångra.

## Markera som skickad (2026-11-04)

- **Vad:** vilken anteckning eller vilket protokoll som helst kan markeras som skickad, via knappen med pappersflygplanet, ⇧⌘E, Arkiv-menyn eller högerklick.
- **Syns:** som ett pappersflygplan på bilagan och i vyn Skickade, och med datum ovanför texten.
- **Vyn Skickade:** markerade anteckningar försvinner ur sin mapp i listan och samlas i Skickade i sidofältet. Det är en vy och ingen mapp, så filen ligger kvar i sin katalog. Tas markeringen bort kommer anteckningen tillbaka. Sökning hittar även skickade anteckningar, och raderade hamnar i Nyligen raderade som vanligt.
- **Sparas** som `sent:` i anteckningens fil, med tidpunkten då den markerades.
- **Markeringen är manuell.** Appen vet inte om något faktiskt skickats, och Kopiera för e-post markerar inget. Ändringsdatumet påverkas inte.

## Siffror i sidofältet (2026-11-04)

- **Normalt** visas bara antalet oskickade protokoll, vilket i praktiken betyder mappen Mötesprotokoll. Övriga mappar visar ingen siffra.
- **När pekaren är över en mapp** visas det totala antalet anteckningar i den.

## Kvar att göra

- **Provkör med riktiga filer** från Outlook och Kalender. Exempelfilerna i testerna är skrivna för hand utifrån formatet.
- **Kontrollera fältet för hand:** utseende, popover och dra och släpp. Claude kan inte ta skärmbilder här, och att släppa filer i verktygsfältet har inte provats.
- **Promptinjektion:** beskrivningen i en `.ics`-fil kommer ofta från någon annan och skickas till AI-tjänsten. Effekten är begränsad, eftersom svaret bara blir en ny anteckning.
