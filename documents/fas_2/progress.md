# Fas 2 – AI: OpenAI-kompatibla endpoints

**Status:** Klart i koden (2026-10-28). Inte provkört mot riktig OpenAI eller Ollama än.
**Plan:** [Approved plan 2026-10-28.md](../Approved%20plan%202026-10-28.md) (byggplanens steg 4)

## Vad som är byggt

Appen kan skapa ett mötesprotokoll från en anteckning med vilken OpenAI-kompatibel server som helst:
- **I molnet:** OpenAI, Azure OpenAI, OpenRouter eller en egen adress.
- **På den här datorn, utan nyckel:** Ollama och LM Studio.

### Flödet
1. Välj en anteckning med mötespunkter och klicka på ✨ **Skapa protokoll** i verktygsfältet (eller tryck ⌥⌘P).
2. Fyll i mötesuppgifterna: titel, tid, plats, organisatör, deltagare och agenda. Välj språk: samma som anteckningarna, svenska eller engelska.
3. Appen skickar uppgifterna och punkterna (som Markdown) till servern och ber om JSON enligt schemat `MeetingProtocol.jsonSchema`.
4. Svaret blir en **ny anteckning**, "Protokoll – <titel>", i samma mapp. Den har de fem avsnitten och ett `meeting:`-block i filen. Originalanteckningen rörs inte.

### Inställningar (⌘,)
- **Förval och adress:** välj ett förval eller ange en egen bas-URL.
- **Nyckelhuvud:** `Authorization: Bearer` eller `api-key` (Azure).
- **API-nyckel:** sparas i Nyckelringen med en nyckel per förval. Den är valfri för servrar på den här datorn.
- **Modell:** "Senaste" eller en vald modell, samt knappen **Testa anslutning**.
- **Integritetstext:** talar om vart datan skickas.

## Filer

| Del | Filer |
|---|---|
| Domän | `Domain/MeetingDetails.swift`, `MeetingProtocol.swift` (med JSON-schema), `ProtocolFormatter.swift`, `JSONValue.swift` |
| Tjänster | `Services/AI/` (`ProtocolGenerator`, `AIEndpointConfiguration`, `AIServiceError`, `HTTPTransport`, `OpenAICompatibleClient`, `ModelResolver`, `OpenAIProtocolGenerator`) och `Services/KeychainService.swift` |
| Gränssnitt | `UI/Settings/` (`AISettings`, `SettingsView`), `UI/Protocol/` (`ProtocolGenerationModel`, `GenerateProtocolSheet`) |
| Konfiguration | `Config/NotesV-Info.plist` (undantag för http mot `localhost`), `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` |

## Beslut

- **Chat Completions, inte Responses API.** Nästan alla kompatibla servrar stöder Chat Completions.
- **Tre sätt att be om JSON,** i den här ordningen: `json_schema` (strikt), `json_object`, ren text med schemat i instruktionen. Svarar servern 400 provas nästa sätt. Det som fungerar kommer appen ihåg per server medan den körs.
- **Svaret kan innehålla mer än JSON.** JSON läses även inuti ```` ```json ````-block och efter `<think>`-avsnitt från resonerande modeller.
- **Mötesinfo kommer från mötesuppgifterna, inte från AI:n,** så den kan inte hittas på. Saknas ansvarig eller datum skrivs en platshållare som "[Ansvarig saknas]".
- **Rubrikerna i protokollet följer protokollets språk,** inte appens. Svenska används för `sv`, annars engelska. Därför ligger de i `ProtocolFormatter.Labels` och inte i översättningsfilen.
- **"Senaste" modell:** den nyaste textmodellen efter `created`. Inbäddnings-, ljud-, bild-, moderations- och realtidsmodeller filtreras bort. Saknar servern `created` används den enda modellen, och finns det flera får användaren välja. Resultatet sparas en dag per server.
- **Nyckeln sparas per förval,** så att den inte försvinner när man ändrar adressen.
- **Manuella möten** får `eventId: ""` i filen. Riktiga Outlook-id kommer i steg 5.
- **Ingen `temperature` skickas,** eftersom vissa resonerande modeller bara accepterar standardvärdet.

## Verifiering

- **66 enhetstester är gröna:**
  - URL-regler och förval
  - förfrågningar och nyckelhuvuden
  - översättning av felkoder
  - modellval och cache
  - reservvägar för JSON
  - formatering av protokollet
  - Nyckelringen
- **Hela kedjan provades mot en låtsasserver på `http://localhost`.**
  - Den sandlådade appen fick göra anropet.
  - Den senaste modellen valdes och inbäddningsmodellen hoppades över.
  - När servern sa nej till `json_schema` föll appen tillbaka på `json_object`.
  - Ingen nyckel skickades.
  - Protokollet fick rätt Markdown.

  Testet var tillfälligt och är inte incheckat.

## Kvar att göra

- **Provkör manuellt:**
  - mot Ollama (`http://localhost:11434/v1`)
  - mot OpenAI med en egen nyckel, som skrivs in i appen och inte i chatten
- **Nyckelringen frågar om lov efter varje bygge.** Under utveckling signeras appen ad hoc och får en ny signatur vid varje bygge. Därför kan macOS fråga om NotesV får använda den sparade nyckeln. Det försvinner när appen signeras med ett riktigt certifikat.
- **Mötesuppgifterna fylls i för hand** tills kalendern kopplas in i steg 5.
- **Svaret visas inte medan det skrivs (ingen strömning).** Hela svaret väntas in, och tidsgränsen är 180 sekunder.
