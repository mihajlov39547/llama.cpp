# UnblockCP

## Verzija 0.2 — selektivno odblokiranje

Posle ažuriranja klikni **Reload** na `chrome://extensions`, pa osveži web
stranice. Potreban je Chrome 119 ili noviji. Nove dozvole `scripting`, `storage`
i pristup sajtovima služe CSS override-u, dijagnostici i čuvanju podešavanja.

Popup ima tri režima koja važe za sve otvorene i buduće stranice:

- **Široko odblokiranje:** automatski presreće standardne blokade kao verzija 0.1.
  Može ometati editore koji koriste sopstvenu copy/paste logiku.
- **Selektivno / dijagnostika:** ostavlja page handlere aktivnim i beleži konkretne
  listenere koji otkazuju relevantne događaje. Isključuju se pojedinačno, po izboru.
- **Isključeno:** vraća izvršavanje isključenih listenera, gasi prečice i uklanja
  CSS override. Instrumentacioni wrapper-i ostaju do reload-a, ali propuštaju
  događaje. Izabrana isključivanja pamte se samo u živom dokumentu i ponovo
  važe ako uključiš selektivni režim. Dugme **Vrati sve listenere** ih briše.

### Kako selektivno ukloniti blokadu

1. U popup-u izaberi **Selektivno / dijagnostika**.
2. Zatvori popup i ponovi blokiranu akciju običnim Ctrl/Meta+C/V/X/A ili mišem.
   Za identifikovanje paste blokade koristi običan Ctrl/Meta+V: Ctrl+Alt+3 ima
   sopstvenu obradu plain text paste-a i namerno zaobilazi page paste handlere.
3. Otvori popup → **Listeneri koji otkazuju događaje** → **Osveži listu**.
4. Prikazuju se tip događaja, ime funkcije ili `(anonimni)`, element, frame,
   capture i broj otkazivanja. Hover nad opisom pokazuje lokaciju registracije.
5. Klikni **Isključi za ovu akciju**, zatvori popup i ponovi akciju. Ako postoji
   više blokada, ponovi postupak. **Vrati listener** poništava konkretnu odluku.

Otkazivanje događaja nije dokaz da je listener štetan: rich text editor takođe
može legitimno pozvati `preventDefault()`. Ne isključujemo automatski sve handlere.

### Šta je implementirano

| Modul | Ponašanje |
| --- | --- |
| CSS restorer | Reverzibilni USER-origin stylesheet za dokument, uključujući author/inline `!important`; zasebni stilovi u otvorenim shadow root-ovima |
| Copy/cut restorer | Identifikovanje i selektivno preskakanje registrovanih listenera koji otkazuju copy/cut |
| Paste restorer | Isto za paste; razlikuje se od naknadnog brisanja teksta kroz `input` |
| Keyboard restorer | Ctrl i Meta, keydown/keyup/keypress; isključeni handler se preskače samo za relevantne prečice, a ostale tastere obrađuje |
| Context-menu restorer | Selektivno isključivanje contextmenu listenera |
| Selection restorer | Selektivno isključivanje selectstart/dragstart listenera uz nezavisan CSS prekidač |
| Beforeinput | Selektivno preskakanje samo za `insertFromPaste*`; običan unos ostaje aktivan |

`listener-registry.js` radi u MAIN svetu na `document_start`: obavija samo
relevantne `addEventListener` registracije, zadržava originalne reference i
prosleđuje `removeEventListener(original, capture)` pravom wrapper-u. Podržani
su anonimni listeneri, `handleEvent` objekti, duplikati, `capture`, `once` i
`AbortSignal`. Isključivanje je reverzibilno preskakanje poziva, a ne trajno
brisanje registracije, čime se zadržava redosled listenera. Native `once` i
abort životni ciklus i dalje važe, uključujući potrošen once listener.

Ne vršimo selektivnu instrumentaciju `oncopy = ...` i inline `oncopy="..."`
handlera; standardne takve zabrane zaobilazi široki režim. Ne možemo videti
registracije pre instrumentacije ili pozive kroz ranije sačuvanu native
`addEventListener` referencu. MAIN svet stranica može menjati: ovo nije zaštita
od aktivnog sabotiranja ekstenzije. Lista je ograničena na 200 stavki po okviru.

Otvoreni Shadow DOM dobija reverzibilne adopted stylesheets, uključujući
dinamički dodat sadržaj. Novi shadow root na postojećem hostu otkriva se najkasnije
pri periodičnoj proveri (oko dve sekunde u aktivnom tabu). Zatvoreni shadow root-ovi
nisu podržani; copy-all nije proširen na sve shadow root-ove ili druge iframe-ove.

Ne blokiramo sve `input` handlere i ne vraćamo nasilno vrednosti koje aplikacija
obriše. Nema posebnih adaptera za Monaco/CodeMirror, OCR-a, zaobilaženja serverskih
pravila ili browser/OS politika. CSS override ne uklanja overlay elemente.

### Testovi nove verzije

Iz `C:\llama.cpp` pokreni `node --test unblockcp/tests/*.test.cjs`.
Automatizovani testovi proveravaju logiku; ne potvrđuju stvarni Chrome clipboard.

Za ručnu Chrome proveru otvori `listener-test.html` uz **Allow access to file URLs**:

1. Selektivno identifikuj i isključi `blockSelection`, `blockCopy`, `blockCut`,
   `blockPaste`, `blockContextMenu`, `blockDrag` i `blockShortcuts`.
2. U keyboard polju proveri da brojač ostalih tastera raste i nakon isključivanja.
3. Dugme za uklanjanje `blockCopy` proverava originalnu `removeEventListener` referencu.
4. Proveri inline `!important`, Shadow DOM i dinamički dodat Shadow DOM.
5. Isključi CSS prekidač: originalna zabrana selekcije treba ponovo da važi.
6. Vrati listenere i proveri da se blokade vraćaju. Proveri i globalni režim Isključeno.
7. Na originalnom `test-page.html` proveri sve četiri prečice, plain/rich paste i undo.

Implementacija prati [Chrome content scripts](https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts),
[Chrome scripting](https://developer.chrome.com/docs/extensions/reference/api/scripting)
i [removeEventListener semantiku](https://developer.mozilla.org/en-US/docs/Web/API/EventTarget/removeEventListener).

Chrome Manifest V3 ekstenzija za odblokiranje uobičajenih zabrana selekcije,
kopiranja, lepljenja i desnog klika. Bez build koraka, servera i zavisnosti.

## Instalacija

1. Otvori `chrome://extensions`.
2. Uključi **Developer mode**.
3. Klikni **Load unpacked** i izaberi `C:\llama.cpp\unblockcp`.
4. Osveži već otvorene stranice.

## Prečice

| Prečica | Akcija |
| --- | --- |
| Ctrl+Alt+1 | Kopira selekciju, uz dostupno formatiranje |
| Ctrl+Alt+2 | Kopira vidljivi tekst trenutnog dokumenta kao plain text |
| Ctrl+Alt+3 | Lepi isključivo tekst |
| Ctrl+Alt+4 | Lepi sadržaj uz formatiranje koje polje podržava |

Pre lepljenja klikni u input, textarea ili contenteditable editor. Prečice
koriste cifre u gornjem redu ili numeričkoj tastaturi. Koristi levi Ctrl i Alt;
AltGr je izuzet da se ne ometa unos posebnih znakova.

Chrome ne dozvoljava Ctrl+Alt u `chrome.commands`, pa prečice obrađuje content
script dok je stranica u fokusu. Ne rade u adresnoj traci ili popup prozoru.

## Opseg i ograničenja

- Obrađuje copy/cut/paste/selectstart/contextmenu/dragstart u capture fazi,
  sprečavajući standardne page handlere da zabrane podrazumevanu akciju.
- CSS vraća `user-select: text` i za naknadno ubačene elemente.
- Normalni Ctrl+C/V/X/A takođe su zaštićeni od uobičajenih key handlera.
- U iframe-u prečice važe za fokusirani dokument; copy-all ne spaja tekst
  drugih iframe-ova, zatvorenih shadow root-ova, slika, canvasa ili neučitanih delova stranice.
- `innerText` kopira renderovani tekst, uključujući tekst van trenutnog ekrana;
  ne kopira automatski vrednosti svih formularskih polja.
- Ne zaobilazi readonly/disabled polja, pristup sadržaju ili zaštite browsera.
- Ne radi na `chrome://` stranicama, Chrome Web Store-u i ugrađenom PDF viewer-u.
  Za lokalne fajlove uključi **Allow access to file URLs** u detaljima ekstenzije.
- Složeni editori koji zavise od sopstvenih paste handlera mogu izgubiti posebne
  funkcije ili zahtevati isključivanje ekstenzije. Nisu pokrivene sve nestandardne
  zabrane, overlay elementi, zatvoreni shadow DOM i ranije registrovani handleri.
- Nativni `document.execCommand` koristi se za clipboard i unos radi zadržavanja
  selekcije, browser sanitizacije i undo ponašanja, uključujući HTTP stranice.
  API je zastareo; funkcionalnost zavisi od podrške Chrome-a. Ne ubacujemo sirovi
  clipboard HTML preko `innerHTML`. U plain text poljima format nije moguć.
- Ekstenzija je aktivna na dozvoljenim stranicama; popup omogućava trenutno
  isključivanje odblokiranja i CSS-a. Za uklanjanje instrumentacije isključi
  ekstenziju kroz Chrome upravljanje ekstenzijama i osveži stranicu.

## Privatnost

Dozvole `clipboardRead` i `clipboardWrite` služe traženim copy/paste operacijama.
Clipboard se ne čita periodično, ne skladišti se i ne šalje na mrežu. Content
script radi na HTTP/HTTPS stranicama i dozvoljenim lokalnim fajlovima.

## Provera

`node --check content.js` proverava sintaksu.

Otvori `test-page.html` u Chrome-u uz dozvoljen pristup lokalnim fajlovima:

1. Bez ekstenzije potvrdi da su selekcija/desni klik/copy/paste blokirani.
2. Uključi ekstenziju i osveži stranicu. Selektuj formatirani pasus i koristi
   Ctrl+Alt+1. U rich text editor nalepi sa Ctrl+Alt+4 (bold/italic ostaju),
   zatim sa Ctrl+Alt+3 (format iz clipboard-a ne prenosi se).
3. Ponovi lepljenje u textarea/input i preko selektovanog postojećeg teksta.
4. Ctrl+Alt+2 treba da kopira tekst dokumenta; proveri ga u Notepad-u.
5. Proveri običan Ctrl+C/V, desni klik, undo, poruku bez selekcije i poruku
   pri pokušaju lepljenja van polja. Readonly polje mora ostati neizmenjeno.
6. Proveri fokusirani iframe, dinamički tekst i numeričke prečice.

Dokumentacija: [Chrome prečice](https://developer.chrome.com/docs/extensions/reference/api/commands),
[Clipboard u ekstenzijama](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Interact_with_the_clipboard).
