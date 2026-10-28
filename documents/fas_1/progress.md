# Fas 1 – Grunden

**Status:** Klar (2026-10-28)
**Plan:** [build-plan.md](../project_start_2026-10-23/build-plan.md), steg 1–3

## Steg 1 – Projektgrund ✅

- `NotesV.xcodeproj` har två mål: appen **NotesV** (macOS 15+, SwiftUI, Swift 6) och testmålet **NotesVTests** (Swift Testing).
- Projektet använder mappar som Xcode synkar automatiskt. Nya filer i `NotesV/` eller `NotesVTests/` kommer med utan att projektfilen behöver ändras.
- Ett delat schema finns (`NotesV.xcscheme`), så att det går att köra `xcodebuild test` från terminalen.
- Appen körs i sandlåda och signeras lokalt (ad hoc). Bundle-id är `se.consid.NotesV` och kan ändras senare.
- Översättningsfilen `Localizable.xcstrings` har engelska som källspråk och svenska översättningar för alla texter i gränssnittet.
- `.gitignore` utesluter `.DS_Store`, `xcuserdata` och byggmappar.

## Steg 2 – Datamodell och Markdown ✅

Allt ligger i `NotesV/Domain/`:

| Fil | Innehåll |
|---|---|
| `RichText.swift` | Text med fetstil, kursiv, understruken och genomstruken text. Lagras i en fast form, så att samma text alltid jämförs lika. |
| `NoteDocument.swift` | Stycken (Titel, Rubrik, Underrubrik, Brödtext, Fast breddsteg), listor (punkt, streck, numrerad, checklista) och tabeller. |
| `Note.swift` | Anteckning, mapp och mötesreferens. |
| `MarkdownCodec.swift` | Översätter mellan anteckning och GitHub Flavored Markdown enligt tabellen i `CLAUDE.md`. |
| `FrontMatter.swift` | YAML-huvudet med id, datum, fäst-status och möte. |
| `FileNaming.swift` | Säkra filnamn, med numrering vid krockar, t.ex. "Möte (2).md". |
| `NoteDateGroup.swift` | Datumgrupperna Idag, Igår, Föregående 7 och 30 dagarna samt månad. |

Lagringen finns i `NotesV/Services/`. `StorageService` är gränssnittet och `LocalStorageService` sparar filerna i appens behållare: `~/Library/Containers/se.consid.NotesV/Data/Library/Application Support/NotesV/Notes/`. Varje mapp i appen är en undermapp där, och varje anteckning är en `.md`-fil. Filen byter namn när titeln ändras.

**Beslut och begränsningar:**
- **Tomma rader:** varje tomt stycke ger en extra tom rad i Markdown-filen. Därför bevaras tomma rader i anteckningen.
- **Mellanslag i början av raden** bevaras bara i brödtext. I rubriker, listor och tabellceller tas de bort, precis som Markdown gör.
- **Fetstil och kursiv på mellanslag** i kanten av en markering tas bort, eftersom Markdown inte kan uttrycka det. Det syns inte i texten.
- **Fast breddsteg** sparas som ett kodblock, och fet eller kursiv text i det försvinner.
- **Tabeller:** den första raden blir rubrikrad i Markdown.
- **Markdown från andra program läses in så gott det går.** Varje rad blir ett eget stycke, listor med 2 eller 3 mellanslags indrag förstås, och okända YAML-nycklar ignoreras.

## Steg 3 – Gränssnitt som i Notes ✅

Allt ligger i `NotesV/UI/`:
- **Tre kolumner:** mappar (`FolderSidebarView`), anteckningslista (`NoteListView`) och editor (`NoteEditorView`).
- **Mappar:**
  - Det finns alltid en standardmapp, "Anteckningar".
  - Man kan skapa, byta namn på och radera mappar.
  - Raderade anteckningar hamnar i "Nyligen raderade". Raderar man dem därifrån försvinner de permanent, efter en bekräftelse.
- **Anteckningslistan:**
  - Fästa anteckningar visas överst och resten grupperas på datum.
  - Varje rad visar titel, datum och förhandsvisning.
  - Högerklick ger valen Fäst, Flytta till och Radera.
  - Sökningen söker i alla mappar.
- **Editorn** (`NotesTextView`, byggd på TextKit 1):
  - Textstilar, fetstil, kursiv, understruken och genomstruken text.
  - Punktlistor, strecklistor, numrerade listor och checklistor med runda bockar som man klickar i.
  - Indrag med Tab och Skift-Tab.
  - Return på en tom listrad avslutar listan.
  - Return efter en rubrik fortsätter med brödtext.
  - Tabeller där Tab och Return flyttar mellan cellerna och man kan lägga till och ta bort rader och kolumner.
  - Kodblock med grå bakgrund och datum ovanför texten.
  - Inklistrad text får stilen där den klistras in.
- **Menyer:** Arkiv (Ny anteckning ⌘N, Ny mapp ⇧⌘N, Fäst anteckning) och Format, med samma kortkommandon som Notes. Verktygsfältet har knapparna Aa, Checklista och Tabell.
- **Sparning:** anteckningar sparas automatiskt 0,6 sekunder efter senaste ändringen, och allt sparas när appen avslutas. Tomma anteckningar sparas inte, precis som i Notes.

## Tester

44 tester i 7 sviter, och alla går igenom. Kör dem med:

```bash
xcodebuild -project NotesV.xcodeproj -scheme NotesV -destination 'platform=macOS' test
```

Testerna täcker:
- att Markdown översätts fram och tillbaka utan förluster, även för knepiga tecken
- front matter och Markdown från andra program
- filnamn och lagring: spara, byta namn, flytta och mappar
- att editorns text och dokumentmodellen stämmer överens
- editorns beteende: Return i listor, formatkommandon, fetstil, Backspace och tabeller

## Kvar att göra och kända brister

- **Gränssnittet har inte provkörts automatiskt.** Claude kunde inte ta skärmbilder i den här miljön, så utseendet behöver kontrolleras för hand. Appen har använts manuellt sedan 2026-10-23.
- **Formatering vid inklistring:** bara ren text klistras in. Formatering inne i appen följer inte med vid kopiera och klistra in.
- **Indrag finns bara för listor.** Brödtext kan inte dras in som i Notes.
- **Appikon saknas.**
