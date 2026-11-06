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

## Vald lagringsmapp (2026-11-05)

- **Välj mapp:** Inställningar → Lagring. Anteckningarna hamnar i en undermapp `NotesV` i den valda mappen, så att annat innehåll inte visas som anteckningsmappar. Heter den valda mappen redan NotesV används den direkt.
- **Byte av mapp kopierar anteckningarna.** De gamla filerna ligger kvar. En anteckning som redan finns i den nya mappen lämnas orörd.
- **Synk:** OneDrive-appen sköter synk och offline-kopia. NotesV pratar aldrig med OneDrive.
- **Mappen saknas:** då används mappen på datorn, och appen ber användaren välja en ny.
- **Ändringar utanför appen:** filerna läses om när appen blir aktiv. Före varje sparning jämförs filen med en hash. Har den ändrats sparas appens version som en ny anteckning, så att båda finns kvar.
- **Behörigheter:** läsning och skrivning av valda filer, och `Config/NotesV.entitlements` för bokmärken.

## Anteckningslistan grupperas efter möte (2026-11-05)

- **Skickat gäller bara protokoll.** Knappen är avstängd på vanliga anteckningar, valet i Arkiv-menyn (⇧⌘E) likaså, och högerklicksvalet visas inte. Även äldre protokoll utan koppling kan markeras, eftersom de ligger i mappen Mötesprotokoll.
- **Tidigare markerade anteckningar** kommer tillbaka till sin mapp och visas inte längre i Skickade. Raden `sent:` ligger kvar i filen men ignoreras.
- **Mappen Anteckningar och egna mappar** visar först anteckningar utan möte under rubriken Saknar mötesinfo, med orange ikon. Sedan kommer en rubrik per mötesdag, senaste dagen först. Inom en dag ligger det senaste mötet först.
- **Fästa anteckningar** ligger fortfarande överst. Saknar en fäst anteckning möte syns det på den orange ikonen i raden.
- **Övriga vyer:** Mötesprotokoll, Skickade, Nyligen raderade och sökning grupperas som tidigare efter ändringsdatum.

## Egna mappar ligger i Notes på disken (2026-11-05)

- **Vad:** mappar som användaren skapar ligger nu i `Notes/` i filsystemet, så att strukturen i Finder och OneDrive stämmer med sidofältet. Mötesprotokoll och Nyligen raderade ligger kvar i roten.
- **Flytt:** vid varje inläsning flyttas mappar som ligger bredvid `Notes` in i den. Det körs varje gång eftersom en annan Mac med en äldre version kan lägga till fler.
- **Finns mappen på båda ställena:** filerna slås ihop. En identisk fil tas bort, och en annan anteckning med samma namn får ett nummer. Andra filer som krockar ligger kvar i den gamla mappen, som då inte tas bort.
- **Misslyckas en flytt** läses mappen från sin gamla plats, och anteckningar flyttas när de sparas.
- **Notes** går inte längre att byta namn på eller radera, eftersom den innehåller de andra mapparna.
- **Äldre versioner:** en äldre version av appen på en annan Mac visar inte mapparna i `Notes/`.

## Appikon (2026-11-05)

- **Motiv:** ett vitt papper med vikt hörn och två textrader på gul bakgrund, med en orange bock som också läses som V:t i NotesV. Ikonen är en egen design.
- **Filer:** bilderna ligger i `Assets.xcassets/AppIcon.appiconset`, och de ritas av `Config/draw-app-icon.swift`.

## Närvaro bekräftas i dialogen (2026-11-06)

- **Varför:** modellen lade alla inbjudna under Närvarande när anteckningarna inte sa något, så listan kunde vara fel.
- **Dialogen** heter nu Granska protokoll och har en sektion Närvaro med en kryssruta per person. Rutorna är förifyllda med modellens förslag. Den som inte är ikryssad hamnar under Frånvarande.
- **Vilka som visas:** inbjudna, organisatören och namn som modellen tagit från anteckningarna. Varje person finns bara i en av listorna.
- **När dialogen visas:** om det finns personer eller åtgärdspunkter. Sektionen för ansvariga visas bara när det finns åtgärdspunkter.
- **Prompten:** modellen ombeds skriva namn exakt som i mötesuppgifterna, så att samma person inte blir två rader. Den kan ändå skriva ett kortare namn när det är oklart vem som menas.
- **Begränsning:** valet görs när protokollet skapas. I ett färdigt protokoll ändrar man texten direkt.

## Release på GitHub (2026-11-06)

- **Flöde:** en tagg som `v0.1.0` startar `.github/workflows/release.yml`, som testar, bygger och publicerar en `.dmg` med kontrollsumma. `ci.yml` kör testerna på pull requests och `main`.
- **Signering:** utan Apple-uppgifter signeras appen ad hoc och publiceras som förhandsversion. macOS blockerar då första starten, och Nyckelringen kan fråga igen efter uppdateringar. Lägg till hemligheterna i README för att notarisera. Det kräver ett betalt Apple Developer-konto.
- **Licens:** alla rättigheter förbehållna, med Daniel Kroon som upphovsrättsinnehavare. Bekräfta att det stämmer gentemot Consid före bred spridning.
- **Ikon:** gul sida med vikt hörn och bock. Den är inte juridiskt granskad.

### Säkerhetsgenomgång före release

Åtgärdat:
- **Fel integritetstext:** en `.local`-server sades ligga på den här datorn, trots att den är en annan dator i nätverket. Texterna använder nu `isOnThisMac`.
- **Flytt av mappar:** valdes en befintlig mapp som hette NotesV kunde orelaterade mappar flyttas in i `Notes/`. Nu flyttas bara tomma mappar och mappar med NotesV-anteckningar.
- **Rader i front matter:** ett `\r\n` i till exempel en mötestitel från en `.ics`-fil kunde lägga till fält i filen. Nu skrivs det som escape-tecken.
- **Promptinjektion:** modellen ombeds behandla mötesuppgifter och anteckningar som data. Det minskar risken men tar inte bort den, så läs protokollet innan det skickas.

Kvar, med låg risk:
- En `.local`-server kan använda vanlig http, så API-nyckeln skickas okrypterad i det lokala nätverket.
- Vid en omdirigering kan URLSession skicka med rubriken `api-key` till en annan server. Det kräver att servern du själv valt beter sig illa.
- Byter man adress under förinställningen Anpassad kan den sparade nyckeln skickas till den nya servern. Det sker bara när användaren själv ändrar adressen.
- `.md`-filer läses utan storleksgräns. En mycket stor fil i en delad mapp kan göra appen långsam.
- Möteslänkar från annat än Outlooks Teams-block, till exempel Zoom, tas inte bort från beskrivningen innan den skickas till AI-tjänsten.
- Dialogen Skapa protokoll nämner bara anteckningarna, medan även mötesuppgifter skickas. Inställningarna säger båda.

Inga fynd: nycklar sparas bara i Nyckelringen, inget loggas, filnamn kan inte lämna mappen, HTML för e-post escapeas, och appen har sandlåda med få behörigheter.

## Kvar att göra

- **Prova mappvalet med en riktig OneDrive-mapp.** Testerna använder tillfälliga mappar, så synk, filer som bara finns online och konfliktkopior från OneDrive är oprovade.
- **Provkör med riktiga filer** från Outlook och Kalender. Exempelfilerna i testerna är skrivna för hand utifrån formatet.
- **Kontrollera fältet för hand:** utseende, popover och dra och släpp. Claude kan inte ta skärmbilder här, och att släppa filer i verktygsfältet har inte provats.
- **Promptinjektion:** beskrivningen i en `.ics`-fil kommer ofta från någon annan och skickas till AI-tjänsten. Effekten är begränsad, eftersom svaret bara blir en ny anteckning.
