# Plan: OpenAI-kompatibla endpoints för protokollgenerering

## Bakgrund

Enligt `CLAUDE.md` och byggplanen (steg 4) ska appen kunna skapa mötesprotokoll med OpenAI som alternativ till Copilot. Du vill att det ska fungera mot **alla servrar som följer OpenAI:s API**, inte bara api.openai.com. Det gäller till exempel OpenAI, Azure OpenAI, OpenRouter, Ollama och LM Studio. I inställningarna anger man adress (bas-URL), nyckel och modell. **Lokala servrar utan nyckel** (Ollama eller LM Studio på `localhost`) ska också fungera.

**Hur det ser ut i koden i dag:**
- Det finns ingen AI- eller nätverkskod än, och ingen `ProtocolGenerator`. Inget anropar `URLSession`.
- Appen körs i sandlåda (`ENABLE_APP_SANDBOX = YES`) men har inte rätt att göra utgående nätverksanrop.
- `Info.plist` genereras automatiskt (`GENERATE_INFOPLIST_FILE = YES`), och det finns ingen undantagsregel för App Transport Security (ATS).
- Det finns redan delar som kan återanvändas:
  - `MarkdownCodec.encodeBody` gör om användarens punkter till Markdown som skickas till modellen.
  - `NoteDocument`, `Block`, `ListItem` och `RichText` används för att bygga upp protokollet som en vanlig anteckning.
  - `MeetingReference` och `Note.meeting` kopplar protokollet till ett möte.
  - Mönstret med ett protokoll plus en lokal implementation, som `StorageService` och `LocalStorageService`, används även här.
  - `NoteStore` sköter flödet för att skapa och spara anteckningar.
  - Testerna är skrivna med Swift Testing.
- **Fas 1 är inte committad.** Hela Xcode-projektet ligger ospårat, gränssnittet har inte provkörts, och `documents/fas_1/` är tom. Det behöver göras klart först (steg 0).

## Lösning i korthet

Vi använder API:et **Chat Completions** (`POST {bas-URL}/chat/completions` och `GET {bas-URL}/models`), eftersom i stort sett alla kompatibla servrar stöder det. Responses API stöds ännu inte av de flesta.

Modellen ska svara med **strukturerad JSON** enligt ett gemensamt schema. Om servern inte stöder `json_schema` provar vi automatiskt enklare varianter. Appen gör sedan om JSON-svaret till formaterad text. Det följer kravet i `CLAUDE.md` att båda AI-tjänsterna ska ge samma struktur.

## Steg

### 0. Avsluta fas 1
- Provkör appen, rätta det som behövs, dokumentera i `documents/fas_1/` och committa.

### 1. Protokollmodell i `Domain/`
- **`MeetingDetails.swift`:** titel, start och slut, plats eller länk, organisatör, deltagare och agenda. Fylls i för hand tills kalendern kopplas in i steg 5.
- **`MeetingProtocol.swift`:** en `Codable`-struktur med samma avsnitt som `CLAUDE.md` beskriver:
  - mötesinfo
  - närvarande och frånvarande
  - agendapunkter, med rubrik och sammanfattning
  - beslut
  - åtgärdspunkter, med uppgift, valfri ansvarig och valfritt datum

  Hit hör också `static let jsonSchema`, det gemensamma schemat som alla AI-tjänster ska följa.
- **`ProtocolFormatter.swift`:** gör om `MeetingProtocol` till ett `NoteDocument`:
  - Titel och rubriker blir `.paragraph(.title/.heading)`.
  - Deltagare och beslut blir punktlistor.
  - Åtgärdspunkter blir checklistor.
  - Saknas ansvarig eller datum skrivs en tydlig platshållare, t.ex. "[Ansvarig saknas]", på rätt språk. Inget hittas på.

### 2. Klient för OpenAI-kompatibla API:er i `Services/AI/`
- **`ProtocolGenerator.swift`:** protokollet `generateProtocol(meeting:notes:language:) async throws -> MeetingProtocol`. Resten av appen känner bara till det.
- **`AIEndpointConfiguration.swift`:**
  - Innehåller bas-URL, typ av autentiseringshuvud och modellval ("Senaste" eller ett specifikt modell-id).
  - Färdiga förval:

    | Förval | Bas-URL |
    |---|---|
    | OpenAI | `https://api.openai.com/v1` |
    | Azure OpenAI | `https://<resurs>.openai.azure.com/openai/v1` |
    | OpenRouter | `https://openrouter.ai/api/v1` |
    | Ollama | `http://localhost:11434/v1` |
    | LM Studio | `http://localhost:1234/v1` |
    | Egen | anges av användaren |

  - Sparas i `UserDefaults`. Nyckeln sparas aldrig där.
  - URL:en kontrolleras: `https` krävs, utom för `localhost`, `127.0.0.1` och `*.local`, där `http` är tillåtet.
- **`HTTPTransport.swift`:** ett litet protokoll ovanpå `URLSession`, så att testerna kan använda en fejkad transport och aldrig anropar riktiga API:er.
- **`OpenAICompatibleClient.swift`:**
  - `listModels()` och `chatCompletion(...)`.
  - Nyckeln skickas som `Authorization: Bearer <nyckel>` eller som `api-key: <nyckel>` (Azure), och utelämnas helt om ingen nyckel finns, som för Ollama.
  - Ingen `temperature` skickas, eftersom vissa resonerande modeller inte accepterar den.
  - Om servern svarar `400` på `response_format: json_schema` försöker klienten igen med `json_object`. Fungerar inte det heller hämtas JSON ur vanlig text, även inom ```` ```json ````-block.
  - Det som fungerar kommer appen ihåg per endpoint medan den körs.
- **`OpenAIProtocolGenerator.swift`:** bygger instruktionerna till modellen:
  - Svara på anteckningarnas språk eller det valda språket.
  - Hitta aldrig på beslut, ansvariga eller datum.

  Användarmeddelandet innehåller mötesuppgifterna och punkterna som Markdown via `MarkdownCodec.encodeBody`. Svaret avkodas till `MeetingProtocol`.
- **`ModelResolver.swift`:** väljer modell enligt "Senaste alltid" i `CLAUDE.md`.
  - Anropar `GET /models` och väljer den nyaste textmodellen efter `created`. Inbäddnings-, ljud-, bild-, moderations- och realtidsmodeller filtreras bort.
  - Om servern saknar `created`, som vissa lokala servrar: en enda modell används direkt, annars får användaren välja.
  - Resultatet sparas en dag per endpoint. Om sökningen misslyckas används den senast sparade modellen och en varning visas.
- **`KeychainService.swift`:** sparar, läser och raderar nyckeln i Nyckelringen (generic password) per endpoint. Byggs med ramverket Security, utan beroenden.
- **Felmeddelanden:** felkoder översätts till begripliga meddelanden på svenska och engelska:

  | Fel | Meddelande |
  |---|---|
  | 401 | fel nyckel |
  | 404 | fel adress eller modell |
  | 429 | för många anrop |
  | ingen anslutning | "Körs Ollama eller LM Studio?" |
  | ogiltig JSON | modellen gav ett svar som inte gick att läsa |

### 3. Sandlåda och nätverk
- Lägg till `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` för appmålet i `project.pbxproj`.
- Skapa `Config/NotesV-Info.plist` med `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`, så att `http://localhost` fungerar, och sätt `INFOPLIST_FILE` till den.
  - Den slås ihop med den genererade plisten.
  - Filen ligger utanför `NotesV/` med flit: annars kopieras den som en resurs av den synkroniserade mappen och bygget krockar.

### 4. Inställningar i `UI/Settings/`
- En `Settings`-scen läggs till i `NotesVApp.swift`. Fliken **AI** innehåller:
  - Val av tjänst: OpenAI-kompatibel. Copilot visas men är avstängt tills steg 7.
  - Förval, bas-URL och typ av autentiseringshuvud.
  - Ett `SecureField` för nyckeln, som sparas i Nyckelringen.
  - Val av modell: "Senaste" plus listan som hämtas, med en knapp för att uppdatera.
  - En knapp **Testa anslutning** som anropar `GET /models`.
  - En integritetstext som säger att data skickas till den valda tjänsten och lämnar Microsoft 365. För `localhost` säger den att data stannar på datorn.

### 5. Skapa protokoll i editorn
- En knapp med `sparkles`-ikon i verktygsfältet i `ContentView.swift` (`NoteDetailView`) och ett menyval under "Note".
- Knappen öppnar `UI/Protocol/GenerateProtocolSheet.swift`, där mötesuppgifterna fylls i för hand och man kan välja språk. Under körningen visas en förloppsindikator och en avbryt-knapp.
- Resultatet blir en **ny anteckning**, "Protokoll – <titel>", i samma mapp med `meeting` ifyllt. Originalanteckningen med punkterna rörs inte.
- Logiken läggs i en ny `ProtocolGenerationModel`, som är `@Observable` och `@MainActor`, så att `NoteStore` inte växer. `NoteStore` får bara en ny metod, `addNote(_:)`.

### 6. Översättning och dokumentation
- Nya texter läggs i `Localizable.xcstrings` med svenska och engelska.
- `CLAUDE.md` uppdateras:
  - "OpenAI API" ändras till "OpenAI-kompatibla API:er (konfigurerbar bas-URL)".
  - Lägg till regeln för val av modell när `created` saknas.
  - Lägg till att `http` bara är tillåtet mot `localhost`.
- `documents/fas_2/` skapas med anteckningar om hur arbetet går.

## Filer

**Nya:**
- `NotesV/Domain/` – `MeetingDetails`, `MeetingProtocol`, `ProtocolFormatter`
- `NotesV/Services/AI/` – `ProtocolGenerator`, `AIEndpointConfiguration`, `HTTPTransport`, `OpenAICompatibleClient`, `OpenAIProtocolGenerator`, `ModelResolver`, `KeychainService`
- `NotesV/UI/Settings/`, `NotesV/UI/Protocol/`
- `Config/NotesV-Info.plist`
- Tester i `NotesVTests/`

**Ändrade:**
- `NotesV/NotesVApp.swift`
- `NotesV/UI/ContentView.swift`
- `NotesV/UI/Commands/NotesCommands.swift`
- `NotesV/UI/NoteStore.swift`
- `NotesV.xcodeproj/project.pbxproj`
- `Localizable.xcstrings`
- `CLAUDE.md`

## Verifiering

**Enhetstester (Swift Testing, fejkad `HTTPTransport`, inga riktiga anrop):**
- Normalisering av bas-URL och regeln https/localhost.
- Förfrågan: rätt sökväg, rätt huvud för Bearer, `api-key` och ingen nyckel, samt att `response_format` finns med.
- Avkodning av ett chat-svar till `MeetingProtocol`.
- Reservvägen från `400` till `json_object` och vidare till JSON ur vanlig text.
- `ModelResolver`: att den nyaste modellen väljs, att modeller som inte är textmodeller filtreras bort, att servrar utan `created` hanteras, och att resultatet sparas och används en dag.
- `ProtocolFormatter`: de fem avsnitten, checklistor och platshållare.
- Översättning av felkoder.
- `KeychainService`: spara, läsa och radera, med en unik tjänst per test.

**Hela kedjan:**
- Kör alla tester med `xcodebuild … test`.
- Provkör manuellt:
  - mot Ollama (`http://localhost:11434/v1`, utan nyckel)
  - mot OpenAI med din egen nyckel, som du skriver in i appen och inte i chatten
- Kontrollera att protokollet blir en ny anteckning med rätt formatering och att `.md`-filen innehåller ett `meeting:`-block.
