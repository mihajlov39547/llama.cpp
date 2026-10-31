# IoA vs IoU in Masking

Source: <https://chatgpt.com/g/g-p-68e2b14ca72c819180c20f69366fcd5c-spatial-mask-merge/c/6a50ace0-2bf4-83eb-9da2-0e1c2826eab1>

> Saved conversation branch. Other branches and internal reasoning are excluded.

## You

@Deep research Review literature on image stitching, tiled inference, and object tracking to find the standard mathematical definitions and differences between Intersection over Union (IoU) and Intersection over Area (IoA) (sometimes called Intersection over Min-Area). Explain why IoA is mathematically superior to IoU for merging a small, highly truncated predicted mask on a tile edge with a larger complete mask from an adjacent tile.

---

## You

da li mozes ovo da pripremis kao latex format \section{predlozi ime} za moj rad koji se bavi temom DOKTORSKA DISERTACIJA 
PRECIZNA SEGMENTACIJA INSTANCI NA VAZDUŠNIM
SNIMCIMA VISOKE REZOLUCIJE KORIŠĆENJEM TILED
INFERENCIJE I GLOBALNE KONSOLIDACIJE MASKI

akademski tekst mozes i grafove i tabele u latex formatu

---

## ChatGPT

Predloženi naziv sekcije je **„Mere prostornog preklapanja za globalnu konsolidaciju maski“**. Naziv je širi od samog poređenja IoU i IoA i dobro se uklapa u temu globalne konsolidacije predikcija dobijenih tiled inferencijom.

:::writing{variant="document" id="41827"}
```latex
% Paketi potrebni za prikazani sadržaj:
% \usepackage{amsmath}
% \usepackage{amssymb}
% \usepackage{booktabs}
% \usepackage{multirow}
% \usepackage{graphicx}
% \usepackage{tikz}
% \usepackage{pgfplots}
% \usepackage{siunitx}
% \usepackage{float}
% \usepackage{cleveref}
%
% \pgfplotsset{compat=1.18}

\section{Mere prostornog preklapanja za globalnu konsolidaciju maski}
\label{sec:mere_prostornog_preklapanja}

Primena tiled inferencije nad vazdušnim snimcima visoke rezolucije omogućava
obradu slika čije dimenzije prevazilaze memorijske i ulazne zahteve modela.
Međutim, podela slike na preklapajuće pločice uvodi problem redundantnih i
parcijalnih predikcija. Ista fizička instanca može biti segmentisana u više
pločica, pri čemu predikcije dobijene u blizini granica pločica često
predstavljaju samo vidljivi fragment objekta. Nakon transformacije lokalnih
predikcija u globalni koordinatni sistem neophodno je utvrditi koje maske
pripadaju istoj instanci i treba ih objediniti.

Pouzdana konsolidacija zahteva izbor odgovarajuće mere prostornog
preklapanja. Najčešće korišćena mera u detekciji objekata, segmentaciji i
praćenju objekata jeste odnos preseka i unije, odnosno
\textit{Intersection over Union} (IoU). Iako je IoU prikladan za procenu
sličnosti regiona približno jednakih veličina, njegova normalizacija površinom
unije može biti nepovoljna kada se porede mala, odsečena maska na granici
pločice i veća, potpunija maska iste instance iz susedne pločice. Za ovaj
problem pogodnija je mera zasnovana na odnosu preseka i površine manjeg
regiona, koja se u literaturi i softverskim implementacijama označava kao
\textit{Intersection over Area} (IoA), \textit{Intersection over Smaller}
(IoS), \textit{Intersection over Minimum Area} (IoM) ili koeficijent
preklapanja.

\subsection{Kontekst tiled inferencije i konsolidacije instanci}
\label{subsec:kontekst_tiled_konsolidacije}

Strategije obrade slike pomoću preklapajućih pločica prvobitno su korišćene
za izvođenje segmentacije nad slikama proizvoljno velikih dimenzija.
Overlap-tile strategija omogućava da centralni deo izlazne pločice bude
izračunat korišćenjem šireg ulaznog konteksta, čime se smanjuju artefakti
izazvani nedostatkom informacija u okolini granice
\cite{ronneberger2015unet,majurski2021exact}. U slučaju semantičke
segmentacije rezultati susednih pločica mogu se objediniti izborom centralnih
zona, interpolacijom ili ponderisanim usrednjavanjem izlaznih mapa.

Kod segmentacije instanci problem je složeniji, jer rezultat nije jedna
globalna mapa klasa, već skup pojedinačnih objekata:
%
\begin{equation}
    \mathcal{P}
    =
    \left\{
        P_i =
        \left(
            M_i,
            c_i,
            s_i,
            T_i
        \right)
    \right\}_{i=1}^{N},
    \label{eq:skup_predikcija}
\end{equation}
%
gde je \(M_i\) binarna maska instance u globalnom koordinatnom sistemu,
\(c_i\) oznaka klase, \(s_i\) pouzdanost predikcije, a \(T_i\) pločica iz
koje je predikcija dobijena. Kada se isti objekat nalazi u preklopnoj zoni
dve ili više pločica, skup \(\mathcal{P}\) može sadržati više predikcija iste
fizičke instance.

Predikcije nastale na granici pločice mogu imati značajno različite
površine. Jedna pločica može sadržati samo mali deo objekta, dok susedna
pločica može obuhvatiti gotovo celu instancu. Zbog toga kriterijum
konsolidacije ne treba da meri samo obostranu sličnost oblika i površine, već
i stepen u kome je manja predikcija sadržana u većoj.

\subsection{Matematička notacija}
\label{subsec:notacija_iou_ioa}

Neka su \(A,B\subseteq\Omega\) dve binarne maske definisane nad domenom slike
\(\Omega\). Površina maske može se definisati kao broj piksela koji pripadaju
maski:
%
\begin{equation}
    |A|
    =
    \sum_{\mathbf{x}\in\Omega}
    \mathbb{I}\!\left[\mathbf{x}\in A\right],
    \label{eq:povrsina_maske}
\end{equation}
%
gde je \(\mathbb{I}[\cdot]\) indikatorska funkcija. Za vektorske poligone
operator \(|\cdot|\) predstavlja geometrijsku površinu regiona.

Radi kraćeg zapisa uvode se oznake
%
\begin{equation}
    a = |A|,
    \qquad
    b = |B|,
    \qquad
    I = |A\cap B|,
    \qquad
    U = |A\cup B| = a+b-I.
    \label{eq:osnovne_oznake_preklapanja}
\end{equation}

Sve razmatrane mere imaju vrednosti u intervalu \([0,1]\), pod uslovom da su
površine maski pozitivne. Vrednost nula označava da maske nemaju zajedničkih
piksela, dok interpretacija vrednosti jedan zavisi od izabrane normalizacije.

\subsection{Odnos preseka i unije}
\label{subsec:definicija_iou}

Odnos preseka i unije definiše se izrazom
%
\begin{equation}
    \operatorname{IoU}(A,B)
    =
    \frac{|A\cap B|}{|A\cup B|}
    =
    \frac{I}{a+b-I}.
    \label{eq:iou_definicija}
\end{equation}

IoU je Jaccardov koeficijent primenjen na prostorne regione. Mera je
simetrična:
%
\begin{equation}
    \operatorname{IoU}(A,B)
    =
    \operatorname{IoU}(B,A),
    \label{eq:iou_simetrija}
\end{equation}
%
i dostiže vrednost jedan samo kada se dve maske podudaraju, izuzimajući
eventualne razlike na skupu mere nula:
%
\begin{equation}
    \operatorname{IoU}(A,B)=1
    \quad\Longleftrightarrow\quad
    A=B.
    \label{eq:iou_jedan}
\end{equation}

Ovo svojstvo čini IoU pogodnim za evaluaciju kvaliteta lokalizacije.
Predikcija dobija visoku vrednost samo kada istovremeno dobro pokriva
referentni objekat i ne sadrži veliku dodatnu površinu. Zbog toga je IoU
standardna mera u evaluaciji detekcije i segmentacije, kao i u velikom broju
algoritama za prostornu asocijaciju objekata
\cite{everingham2010pascal,lin2014coco,wu2013tracking,bewley2016sort}.

Međutim, ista osobina predstavlja ograničenje prilikom konsolidacije
parcijalnih predikcija. Ako je jedna maska potpuno sadržana u drugoj,
odnosno ako je \(A\subseteq B\), tada važi
%
\begin{equation}
    |A\cap B|=|A|,
    \qquad
    |A\cup B|=|B|,
\end{equation}
%
pa se IoU svodi na odnos njihovih površina:
%
\begin{equation}
    \operatorname{IoU}(A,B)
    =
    \frac{|A|}{|B|}.
    \label{eq:iou_sadrzavanje}
\end{equation}

Prema tome, čak i potpuno sadržavanje manje maske u većoj ne proizvodi
visoku IoU vrednost ako se njihove površine značajno razlikuju.

\subsection{Usmereni odnos preseka i površine}
\label{subsec:definicija_usmerenog_ioa}

Naziv \textit{Intersection over Area} nije potpuno jednoznačan, jer je
neophodno navesti površinu koje maske se koristi u imeniocu. Usmereni IoA u
odnosu na masku \(A\) definiše se kao
%
\begin{equation}
    \operatorname{IoA}_{A}(A,B)
    =
    \frac{|A\cap B|}{|A|}
    =
    \frac{I}{a},
    \label{eq:ioa_a}
\end{equation}
%
dok je odgovarajuća mera u odnosu na masku \(B\)
%
\begin{equation}
    \operatorname{IoA}_{B}(A,B)
    =
    \frac{|A\cap B|}{|B|}
    =
    \frac{I}{b}.
    \label{eq:ioa_b}
\end{equation}

Za razliku od IoU, usmereni IoA nije simetričan:
%
\begin{equation}
    \operatorname{IoA}_{A}(A,B)
    \neq
    \operatorname{IoA}_{B}(A,B)
\end{equation}
%
u opštem slučaju. Semantički, \(\operatorname{IoA}_{A}(A,B)\) odgovara na
pitanje: \textit{koji deo regiona \(A\) je pokriven regionom \(B\)?}

Ako je \(A\subseteq B\), tada je
%
\begin{equation}
    \operatorname{IoA}_{A}(A,B)=1,
    \qquad
    \operatorname{IoA}_{B}(A,B)=\frac{|A|}{|B|}.
    \label{eq:ioa_sadrzavanje}
\end{equation}

Usmerena normalizacija koristi se u više sistema za evaluaciju i filtriranje
detekcija. Na primer, COCO evaluacioni protokol za regione označene kao
\texttt{iscrowd} koristi presek normalizovan površinom detekcije, čime
dozvoljava da detekcija bude potpuno sadržana u većem grupnom regionu bez
kažnjavanja zbog velike razlike u površini \cite{lin2014coco,cocoapi}.
Slične varijante se u bibliotekama za detekciju označavaju i kao
\textit{Intersection over Foreground}.

\subsection{Odnos preseka i manje površine}
\label{subsec:definicija_iom}

Za konsolidaciju bez unapred određenog smera može se koristiti simetrična
varijanta normalizovana površinom manje maske:
%
\begin{equation}
    \operatorname{IoM}(A,B)
    =
    \frac{|A\cap B|}
         {\min\left(|A|,|B|\right)}.
    \label{eq:iom_definicija}
\end{equation}

U literaturi i softverskim bibliotekama ova mera može biti označena kao
\(\operatorname{IoM}\), \(\operatorname{IoS}\), \(\operatorname{IOS}\),
\textit{Intersection over Min-Area}, \textit{Intersection over Smaller} ili
Szymkiewicz--Simpsonov koeficijent preklapanja. U okviru SAHI pristupa za
sliced inferenciju koristi se oznaka \texttt{IOS}, pri čemu je mera
definisana kao presek podeljen površinom manjeg regiona
\cite{akyon2022sahi,sahiRepository}.

Mera \(\operatorname{IoM}\) može se predstaviti i kao maksimum dva usmerena
IoA izraza:
%
\begin{equation}
    \operatorname{IoM}(A,B)
    =
    \max
    \left\{
        \operatorname{IoA}_{A}(A,B),
        \operatorname{IoA}_{B}(A,B)
    \right\}.
    \label{eq:iom_kao_maksimum}
\end{equation}

Pošto se u imeniocu koristi manja površina, \(\operatorname{IoM}\) je
simetrična:
%
\begin{equation}
    \operatorname{IoM}(A,B)
    =
    \operatorname{IoM}(B,A),
\end{equation}
%
ali, za razliku od IoU, dostiže vrednost jedan kada je jedna maska potpuno
sadržana u drugoj:
%
\begin{equation}
    \operatorname{IoM}(A,B)=1
    \quad\Longleftrightarrow\quad
    A\subseteq B
    \;\lor\;
    B\subseteq A.
    \label{eq:iom_jedan}
\end{equation}

Ovo svojstvo odgovara semantici konsolidacije parcijalnih predikcija:
potpuno sadržana manja maska može predstavljati fragment iste instance, čak
i kada njena površina čini samo mali deo potpunije maske.

\subsection{Poređenje osnovnih svojstava}
\label{subsec:poredjenje_iou_ioa_iom}

Osnovne razlike između razmatranih mera prikazane su u
\cref{tab:poredjenje_iou_ioa_iom}.

\begin{table}[H]
    \centering
    \caption{Poređenje mera prostornog preklapanja.}
    \label{tab:poredjenje_iou_ioa_iom}
    \small
    \begin{tabular}{
        p{0.17\textwidth}
        p{0.22\textwidth}
        p{0.10\textwidth}
        p{0.22\textwidth}
        p{0.20\textwidth}
    }
        \toprule
        \textbf{Mera} &
        \textbf{Definicija} &
        \textbf{Simetrična} &
        \textbf{Uslov za vrednost 1} &
        \textbf{Dominantna interpretacija} \\
        \midrule

        IoU &
        \(\displaystyle
        \frac{|A\cap B|}{|A\cup B|}
        \) &
        da &
        \(A=B\) &
        Obostrana sličnost regiona, uključujući slaganje njihovih površina.
        \\[1.2em]

        \(\operatorname{IoA}_{A}\) &
        \(\displaystyle
        \frac{|A\cap B|}{|A|}
        \) &
        ne &
        \(A\subseteq B\) &
        Udeo maske \(A\) koji je pokriven maskom \(B\).
        \\[1.2em]

        \(\operatorname{IoA}_{B}\) &
        \(\displaystyle
        \frac{|A\cap B|}{|B|}
        \) &
        ne &
        \(B\subseteq A\) &
        Udeo maske \(B\) koji je pokriven maskom \(A\).
        \\[1.2em]

        IoM/IoS &
        \(\displaystyle
        \frac{|A\cap B|}
             {\min(|A|,|B|)}
        \) &
        da &
        \(A\subseteq B\) ili \(B\subseteq A\) &
        Pokrivenost manje maske većom maskom.
        \\
        \bottomrule
    \end{tabular}
\end{table}

Za sve maske pozitivne površine važi
%
\begin{equation}
    \operatorname{IoU}(A,B)
    \leq
    \operatorname{IoM}(A,B).
    \label{eq:iou_manje_iom}
\end{equation}

Dokaz sledi iz činjenice da je
%
\begin{equation}
    |A\cup B|
    \geq
    \max(|A|,|B|)
    \geq
    \min(|A|,|B|),
\end{equation}
%
pa je
%
\begin{equation}
    \frac{|A\cap B|}{|A\cup B|}
    \leq
    \frac{|A\cap B|}{\min(|A|,|B|)}.
\end{equation}

Pored toga, pošto je
\(
|A\cap B|\leq\min(|A|,|B|)
\)
i
\(
|A\cup B|\geq\max(|A|,|B|)
\),
dobija se gornja granica
%
\begin{equation}
    \operatorname{IoU}(A,B)
    \leq
    \frac{\min(|A|,|B|)}
         {\max(|A|,|B|)}.
    \label{eq:iou_gornja_granica_odnosa_povrsina}
\end{equation}

Iz \cref{eq:iou_gornja_granica_odnosa_povrsina} neposredno sledi da velika
razlika u površinama dve maske unapred ograničava najveću moguću IoU
vrednost. Ovo ograničenje postoji čak i kada je manja maska u potpunosti
sadržana u većoj.

\subsection{Analiza odsečene maske na granici pločice}
\label{subsec:analiza_odsecene_maske}

Neka je \(S\) mala maska dobijena na granici jedne pločice, a \(L\) veća,
potpunija maska iste instance dobijena iz susedne pločice. Pretpostavlja se
da je
%
\begin{equation}
    |S|\leq |L|.
\end{equation}

Uvodi se odnos površina
%
\begin{equation}
    \tau
    =
    \frac{|S|}{|L|},
    \qquad
    0<\tau\leq 1,
    \label{eq:tau_odnos_povrsina}
\end{equation}
%
kao i koeficijent pokrivenosti male maske
%
\begin{equation}
    c
    =
    \frac{|S\cap L|}{|S|},
    \qquad
    0\leq c\leq 1.
    \label{eq:c_pokrivenost_fragmenta}
\end{equation}

Koeficijent \(c\) predstavlja deo odsečene maske koji je obuhvaćen većom
maskom. Iz \cref{eq:tau_odnos_povrsina,eq:c_pokrivenost_fragmenta} sledi
%
\begin{equation}
    |S\cap L|
    =
    c|S|
    =
    c\tau|L|.
    \label{eq:presek_fragmenta}
\end{equation}

Usmereni IoA u odnosu na fragment jednak je
%
\begin{equation}
    \operatorname{IoA}_{S}(S,L)
    =
    \frac{|S\cap L|}{|S|}
    =
    c.
    \label{eq:ioa_fragment_c}
\end{equation}

Pošto je \(S\) manja maska, ista vrednost se dobija i za IoM:
%
\begin{equation}
    \operatorname{IoM}(S,L)
    =
    \frac{|S\cap L|}{\min(|S|,|L|)}
    =
    \frac{|S\cap L|}{|S|}
    =
    c.
    \label{eq:iom_fragment_c}
\end{equation}

Za IoU se dobija
%
\begin{align}
    \operatorname{IoU}(S,L)
    &=
    \frac{|S\cap L|}
         {|S|+|L|-|S\cap L|}
    \nonumber\\
    &=
    \frac{c\tau|L|}
         {\tau|L|+|L|-c\tau|L|}
    \nonumber\\
    &=
    \frac{c\tau}
         {1+\tau-c\tau}.
    \label{eq:iou_fragment_opsti_oblik}
\end{align}

Pošto je
%
\begin{equation}
    1+\tau-c\tau
    =
    1+\tau(1-c)
    \geq 1,
\end{equation}
%
važi
%
\begin{equation}
    \operatorname{IoU}(S,L)
    \leq
    c\tau.
    \label{eq:iou_fragment_granica}
\end{equation}

Jednačine
\cref{eq:ioa_fragment_c,eq:iom_fragment_c,eq:iou_fragment_opsti_oblik}
pokazuju fundamentalnu razliku između mera. IoA i IoM zavise samo od
pokrivenosti fragmenta \(c\), dok IoU dodatno zavisi od odnosa površina
\(\tau\). Kada je fragment veoma mali, odnosno kada
\(\tau\rightarrow 0\), važi
%
\begin{equation}
    \lim_{\tau\rightarrow 0}
    \operatorname{IoU}(S,L)
    =
    0,
    \label{eq:iou_limit_mali_fragment}
\end{equation}
%
čak i kada je \(c\) blisko jedinici. Istovremeno,
%
\begin{equation}
    \operatorname{IoA}_{S}(S,L)
    =
    \operatorname{IoM}(S,L)
    =
    c
\end{equation}
%
ostaje nepromenjeno.

U idealnom slučaju potpunog sadržavanja, \(S\subseteq L\), važi \(c=1\), pa
se izrazi svode na
%
\begin{equation}
    \operatorname{IoU}(S,L)=\tau,
    \qquad
    \operatorname{IoA}_{S}(S,L)=1,
    \qquad
    \operatorname{IoM}(S,L)=1.
    \label{eq:idealno_sadrzavanje_fragmenta}
\end{equation}

Ako mala maska predstavlja samo \SI{10}{\percent} površine potpune maske,
tada je \(\tau=0.1\). Čak i kada je ona potpuno sadržana u većoj maski,
dobija se
%
\begin{equation}
    \operatorname{IoU}(S,L)=0.1,
    \qquad
    \operatorname{IoA}_{S}(S,L)=1.
\end{equation}

Prema standardnom IoU pragu od \(0.5\), takve maske bile bi proglašene
nepovezanim, iako manja maska ne sadrži nijedan piksel izvan veće maske.
IoU u ovom slučaju ne meri verovatnoću pripadnosti istoj instanci, već
pretežno kažnjava razliku u veličinama dve predikcije.

\subsection{Uticaj praga za spajanje}
\label{subsec:uticaj_praga_spajanja}

Neka se maske spajaju ako je
%
\begin{equation}
    \operatorname{IoU}(S,L)\geq\theta_{\mathrm{IoU}}.
    \label{eq:iou_uslov_spajanja}
\end{equation}

Korišćenjem \cref{eq:iou_fragment_opsti_oblik} dobija se
%
\begin{equation}
    \frac{c\tau}{1+\tau-c\tau}
    \geq
    \theta_{\mathrm{IoU}}.
\end{equation}

Rešavanjem po \(\tau\) sledi
%
\begin{equation}
    \tau
    \geq
    \frac{\theta_{\mathrm{IoU}}}
    {c(1+\theta_{\mathrm{IoU}})
    -\theta_{\mathrm{IoU}}},
    \label{eq:minimalni_tau_za_iou}
\end{equation}
%
pod uslovom da je imenilac pozitivan.

Za potpuno sadržavanje, \(c=1\), uslov se pojednostavljuje na
%
\begin{equation}
    \tau
    \geq
    \theta_{\mathrm{IoU}}.
    \label{eq:minimalni_tau_potpuno_sadrzavanje}
\end{equation}

Drugim rečima, ako je prag
\(\theta_{\mathrm{IoU}}=0.5\), nijedan potpuno sadržan fragment koji zauzima
manje od polovine površine veće maske ne može biti spojen. Ovo nije posledica
lošeg prostornog slaganja, već direktna posledica izbora unije kao
normalizujuće površine.

Za IoA ili IoM kriterijum
%
\begin{equation}
    \operatorname{IoA}_{S}(S,L)
    =
    \operatorname{IoM}(S,L)
    \geq
    \theta_{\mathrm{IoA}}
\end{equation}
%
ekvivalentan je jednostavnom uslovu
%
\begin{equation}
    c\geq\theta_{\mathrm{IoA}},
    \label{eq:ioa_uslov_pokrivenosti}
\end{equation}
%
koji ne zavisi od odnosa površina. Time se neposredno testira da li je
dovoljan deo odsečenog fragmenta pokriven potpunijom predikcijom.

\subsection{Numerički primeri}
\label{subsec:numericki_primeri_iou_ioa}

U \cref{tab:numericki_primeri_iou_ioa} prikazane su vrednosti mera za tri
karakteristična slučaja.

\begin{table}[H]
    \centering
    \caption{Numeričko poređenje IoU i IoA/IoM za različite odnose maski.}
    \label{tab:numericki_primeri_iou_ioa}
    \small
    \begin{tabular}{
        p{0.30\textwidth}
        S[table-format=4.0]
        S[table-format=4.0]
        S[table-format=4.0]
        S[table-format=1.4]
        S[table-format=1.3]
        S[table-format=1.3]
    }
        \toprule
        {\textbf{Slučaj}} &
        {\(\boldsymbol{|S|}\)} &
        {\(\boldsymbol{|L|}\)} &
        {\(\boldsymbol{|S\cap L|}\)} &
        {\textbf{IoU}} &
        {\(\boldsymbol{\operatorname{IoA}_{S}}\)} &
        {\textbf{IoM}} \\
        \midrule

        Potpuno sadržan mali fragment
        & 120 & 1000 & 120 & 0.1200 & 1.000 & 1.000 \\

        \SI{90}{\percent} fragmenta pokriveno
        & 120 & 1000 & 108 & 0.1067 & 0.900 & 0.900 \\

        Predikcije sličnih površina
        & 500 & 520 & 430 & 0.7288 & 0.860 & 0.860 \\

        \bottomrule
    \end{tabular}
\end{table}

Kod predikcija sličnih površina IoU zadržava visoku vrednost i predstavlja
dobar indikator njihove obostrane sličnosti. Kod izrazito različitih
površina IoU postaje nizak čak i kada je pokrivenost manjeg regiona potpuna
ili veoma visoka. IoA i IoM, nasuprot tome, zadržavaju direktnu
interpretaciju procenta pokrivenosti fragmenta.

\subsection{Grafička analiza zavisnosti od veličine fragmenta}
\label{subsec:graficka_analiza_iou_ioa}

Na \cref{fig:iou_ioa_zavisnost_tau} prikazana je zavisnost IoU i IoA od
odnosa površina \(\tau=|S|/|L|\), za različite vrednosti pokrivenosti
fragmenta \(c\).

\begin{figure}[H]
    \centering
    \begin{tikzpicture}
        \begin{axis}[
            width=0.92\textwidth,
            height=0.55\textwidth,
            xmin=0,
            xmax=1,
            ymin=0,
            ymax=1.05,
            xlabel={Odnos površina \(\tau=|S|/|L|\)},
            ylabel={Vrednost mere preklapanja},
            grid=major,
            legend style={
                at={(0.5,-0.24)},
                anchor=north,
                legend columns=2
            },
            domain=0.001:1,
            samples=200,
            no markers
        ]

            % IoU za c = 1.0
            \addplot {x};
            \addlegendentry{
                \(\operatorname{IoU},\,c=1.0\)
            }

            % IoA za c = 1.0
            \addplot {1};
            \addlegendentry{
                \(\operatorname{IoA}_{S},\,c=1.0\)
            }

            % IoU za c = 0.9
            \addplot {(0.9*x)/(1+x-0.9*x)};
            \addlegendentry{
                \(\operatorname{IoU},\,c=0.9\)
            }

            % IoA za c = 0.9
            \addplot {0.9};
            \addlegendentry{
                \(\operatorname{IoA}_{S},\,c=0.9\)
            }

            % IoU prag 0.5
            \addplot[dashed] {0.5};
            \addlegendentry{
                prag \(0.5\)
            }

        \end{axis}
    \end{tikzpicture}
    \caption{
        Zavisnost IoU i IoA od odnosa površine odsečenog fragmenta i
        potpunije maske. IoA ostaje jednak pokrivenosti fragmenta \(c\),
        dok IoU opada sa smanjenjem relativne veličine fragmenta.
    }
    \label{fig:iou_ioa_zavisnost_tau}
\end{figure}

Grafik pokazuje da se IoU približava nuli kada relativna površina fragmenta
opada. Za potpuno sadržavanje, \(c=1\), IoU je direktno jednak
\(\tau\). Nasuprot tome, IoA ostaje jednak jedinici nezavisno od veličine
fragmenta. Za delimično sadržavanje, na primer \(c=0.9\), IoA ostaje jednak
\(0.9\), dok IoU ostaje nizak za sve male vrednosti \(\tau\).

\subsection{Ilustracija odnosa fragmenta i potpune maske}
\label{subsec:ilustracija_fragmenta}

\begin{figure}[H]
    \centering
    \begin{tikzpicture}[scale=0.85]

        % Tile 1
        \draw[thick] (0,0) rectangle (6,5);
        \node at (3,5.35) {Pločica \(T_1\)};

        % Tile 2
        \draw[thick] (5,0) rectangle (11,5);
        \node at (8,5.35) {Pločica \(T_2\)};

        % Overlap area
        \draw[dashed] (5,0) rectangle (6,5);
        \node[rotate=90] at (5.5,2.5) {preklopna zona};

        % Large complete-ish object
        \draw[very thick, rounded corners=18pt]
            (4.7,1.0)
            .. controls (5.2,0.7) and (7.0,0.6) .. (8.3,1.1)
            .. controls (9.2,1.6) and (9.3,3.3) .. (8.4,4.0)
            .. controls (7.5,4.6) and (5.9,4.4) .. (5.2,3.7)
            .. controls (4.6,3.0) and (4.2,1.7) .. cycle;

        % Small truncated mask
        \fill[pattern=north east lines]
            (4.7,1.0)
            .. controls (5.2,0.7) and (5.7,0.8) .. (6.0,0.9)
            -- (6.0,4.3)
            .. controls (5.7,4.2) and (5.4,4.0) .. (5.2,3.7)
            .. controls (4.6,3.0) and (4.2,1.7) .. cycle;

        \node[align=center] at (2.2,2.5)
            {Odsečena\\maska \(S\)};

        \draw[->, thick] (3.2,2.5) -- (4.9,2.5);

        \node[align=center] at (9.5,2.5)
            {Potpunija\\maska \(L\)};

        \draw[->, thick] (8.8,2.5) -- (7.8,2.5);

    \end{tikzpicture}
    \caption{
        Ilustracija nastanka male odsečene maske \(S\) i veće, potpunije
        maske \(L\) iste instance u susednim preklapajućim pločicama.
        Nakon transformacije u globalni koordinatni sistem maska \(S\)
        može biti skoro potpuno sadržana u maski \(L\), iako se njihove
        površine značajno razlikuju.
    }
    \label{fig:fragment_i_potpuna_maska}
\end{figure}

\subsection{Zašto je IoA pogodniji za konsolidaciju odsečenih maski}
\label{subsec:zasto_ioa_pogodniji}

Za konsolidaciju maski treba razlikovati dva matematički različita pitanja:

\begin{enumerate}
    \item Koliko su dva regiona slična u pogledu položaja, oblika i
    površine?
    \item Da li je manja predikcija uglavnom sadržana u većoj predikciji?
\end{enumerate}

IoU odgovara prvenstveno na prvo pitanje. Visoka IoU vrednost zahteva da
regioni imaju i veliki zajednički deo i približno jednake ukupne površine.
Zato je IoU odgovarajući kriterijum za evaluaciju kvaliteta segmentacije,
gde predikcija ne treba ni da propusti veliki deo objekta ni da obuhvati
veliku dodatnu površinu.

Prilikom konsolidacije odsečenih predikcija cilj je drugačiji. Mala maska
nije nužno loša aproksimacija potpune instance, već rezultat ograničenog
vidnog polja pločice. Njena mala površina zato ne predstavlja dokaz da
pripada drugom objektu. Relevantno pitanje jeste da li je gotovo ceo njen
sadržaj obuhvaćen potpunijom maskom iz susedne pločice.

IoA nad manjom maskom neposredno meri ovu osobinu:
%
\begin{equation}
    \operatorname{IoA}_{S}(S,L)
    =
    \frac{\text{deo fragmenta pokriven većom maskom}}
         {\text{ukupna površina fragmenta}}.
\end{equation}

Zbog toga je IoA matematički primereniji kriterijum za ovaj specifični
problem. Njegova prednost nije u tome što je univerzalno bolja mera
preklapanja, već u tome što je njegova normalizacija usklađena sa
semantikom hipoteze koja se proverava. Za granični fragment proverava se
pokrivenost manjeg kandidata, a ne jednakost površina dva kandidata.

Može se zaključiti da je IoA/IoM superiorniji od IoU u datom scenariju iz
sledećih razloga:

\begin{enumerate}
    \item \textbf{Invarijantnost u odnosu na veličinu potpunije maske.}
    Za fiksnu pokrivenost fragmenta, IoA ne opada kada površina veće maske
    raste.

    \item \textbf{Ispravna interpretacija potpunog sadržavanja.}
    Potpuno sadržan fragment dobija vrednost jedan, nezavisno od toga koliko
    je mali u odnosu na potpunu masku.

    \item \textbf{Nezavisnost od odnosa površina.}
    Uslov za spajanje zavisi od pokrivenosti \(c\), a ne od relativne
    veličine fragmenta \(\tau\).

    \item \textbf{Mogućnost upotrebe visokog praga.}
    Prag IoA može ostati visok, na primer između \(0.7\) i \(0.9\), bez
    automatskog odbacivanja malih validnih fragmenata.

    \item \textbf{Bolja usklađenost sa procesom nastanka predikcija.}
    Razlika u površini očekivana je posledica sečenja slike, a ne nužno
    indikator različitih instanci.
\end{enumerate}

\subsection{Ograničenja normalizacije manjom površinom}
\label{subsec:ogranicenja_ioa}

Visoka IoA ili IoM vrednost nije sama po sebi dovoljan dokaz da dve maske
pripadaju istoj instanci. Ako se mali objekat nalazi unutar maske većeg
objekta iste klase, IoM može biti visok ili jednak jedinici, iako su u
pitanju različite fizičke instance. Ovo je posebno važno u gustim scenama
sa međusobno bliskim ili ugnježdenim objektima.

Zbog toga kriterijum zasnovan na manjoj površini treba primenjivati uz
dodatna prostorna i semantička ograničenja. Kandidati za spajanje treba da:

\begin{itemize}
    \item pripadaju istoj klasi;
    \item potiču iz različitih, prostorno susednih pločica;
    \item budu prisutni u zajedničkoj preklopnoj zoni pločica;
    \item imaju najmanje jednu masku koja dodiruje ili se nalazi u blizini
    granice svoje izvorne pločice;
    \item zadovolje ograničenje udaljenosti centroida ili granica maski;
    \item imaju kompatibilne vrednosti pouzdanosti i geometrijske osobine.
\end{itemize}

Neka je \(e_i\in\{0,1\}\) indikator da predikcija \(P_i\) dodiruje granicu
svoje pločice. Kriterijum za formiranje kandidatske veze između predikcija
\(P_i\) i \(P_j\) može se zapisati kao
%
\begin{equation}
    E_{ij}
    =
    \mathbb{I}
    \left[
        c_i=c_j
    \right]
    \mathbb{I}
    \left[
        T_i\sim T_j
    \right]
    \mathbb{I}
    \left[
        e_i\lor e_j
    \right]
    \mathbb{I}
    \left[
        \operatorname{IoM}(M_i,M_j)
        \geq
        \theta_{\mathrm{IoM}}
    \right],
    \label{eq:kandidatska_veza_iom}
\end{equation}
%
gde \(T_i\sim T_j\) označava da su pločice prostorno susedne.

Na ovaj način IoM se ne primenjuje globalno na sve maske iste klase, već
samo na parove za koje proces tiled inferencije daje opravdanje da mogu
predstavljati duplikate ili fragmente iste instance.

\subsection{Kombinovani kriterijum IoU i IoA}
\label{subsec:kombinovani_kriterijum}

IoU i IoA ne treba posmatrati kao međusobno isključive mere. One mere
različite osobine i mogu se kombinovati u jedinstvenom postupku globalne
konsolidacije.

Za maske sličnih površina IoU je informativan, jer potvrđuje i prostorno
preklapanje i slaganje veličina. Za parove sa velikom razlikom u površinama,
posebno kada manja maska dodiruje granicu pločice, prikladnije je koristiti
IoA ili IoM.

Odnos površina može se definisati kao
%
\begin{equation}
    r(A,B)
    =
    \frac{\min(|A|,|B|)}
         {\max(|A|,|B|)}.
    \label{eq:odnos_povrsina_r}
\end{equation}

Kombinovano pravilo može biti zapisano kao
%
\begin{equation}
    \operatorname{merge}(A,B)
    =
    \begin{cases}
        1,
        &
        r(A,B)\geq\rho
        \;\land\;
        \operatorname{IoU}(A,B)
        \geq\theta_{\mathrm{IoU}},
        \\[0.6em]
        1,
        &
        r(A,B)<\rho
        \;\land\;
        \operatorname{IoM}(A,B)
        \geq\theta_{\mathrm{IoM}}
        \;\land\;
        e_A\lor e_B,
        \\[0.6em]
        0,
        &
        \text{u ostalim slučajevima},
    \end{cases}
    \label{eq:kombinovano_pravilo_spajanja}
\end{equation}
%
gde je \(\rho\) prag sličnosti površina, a
\(\theta_{\mathrm{IoU}}\) i \(\theta_{\mathrm{IoM}}\) odgovarajući pragovi
preklapanja.

Alternativno, može se koristiti jedinstvena kompozitna mera
%
\begin{equation}
    S(A,B)
    =
    w(A,B)\operatorname{IoU}(A,B)
    +
    \left[1-w(A,B)\right]\operatorname{IoM}(A,B),
    \label{eq:kompozitna_mera}
\end{equation}
%
gde težina \(w(A,B)\) raste sa sličnošću površina maski. Na primer,
%
\begin{equation}
    w(A,B)=r(A,B).
\end{equation}

Tada se za maske sličnih površina veća težina dodeljuje IoU meri, dok se za
izrazito različite površine odluka više zasniva na pokrivenosti manjeg
regiona.

Ipak, diskretno pravilo iz \cref{eq:kombinovano_pravilo_spajanja} može biti
jednostavnije za interpretaciju, analizu grešaka i određivanje pragova.
Optimalne vrednosti parametara treba odrediti eksperimentalno na
validacionom skupu koji reprezentativno obuhvata objekte presečene
granicama pločica.

\subsection{Primena na maske i granične pravougaonike}
\label{subsec:mask_level_box_level}

Mere preklapanja mogu se računati na nivou graničnih pravougaonika ili
binarnih maski. Za granične pravougaonike izračunavanje je jednostavnije i
računski efikasnije, ali pravougaonici mogu obuhvatiti značajnu pozadinu,
posebno kod izduženih, zakrivljenih ili nepravilnih objekata karakterističnih
za vazdušne snimke.

Ako su dostupne maske instanci, konačna odluka o konsolidaciji treba
primarno da se zasniva na mask-level preklapanju:
%
\begin{equation}
    \operatorname{IoM}_{\mathrm{mask}}(M_i,M_j)
    =
    \frac{|M_i\cap M_j|}
         {\min(|M_i|,|M_j|)}.
    \label{eq:mask_level_iom}
\end{equation}

Box-level mera može se koristiti kao jeftin preliminarni filter:
%
\begin{equation}
    \operatorname{IoM}_{\mathrm{box}}(B_i,B_j)
    \geq
    \theta_{\mathrm{box}},
    \label{eq:box_level_filter}
\end{equation}
%
nakon čega se mask-level preklapanje računa samo za parove koji zadovolje
prostorni filter. Takav dvostepeni postupak smanjuje broj skupih operacija
nad maskama, naročito kada je broj predikcija veliki.

\subsection{Veza sa globalnom konsolidacijom maski}
\label{subsec:veza_sa_globalnom_konsolidacijom}

Nakon identifikovanja kompatibilnih parova, predikcije se mogu predstaviti
kao neusmeren graf
%
\begin{equation}
    \mathcal{G}
    =
    \left(
        \mathcal{V},
        \mathcal{E}
    \right),
    \label{eq:graf_konsolidacije}
\end{equation}
%
gde svaki čvor \(v_i\in\mathcal{V}\) predstavlja jednu predikciju, a grana
\((v_i,v_j)\in\mathcal{E}\) označava da predikcije zadovoljavaju kriterijum
pripadnosti istoj instanci.

Komponente povezanosti ili klasteri ovog grafa predstavljaju grupe maski
koje treba objediniti. Za klaster
\(\mathcal{C}_k\subseteq\mathcal{V}\) konsolidovana maska može biti
formirana unijom:
%
\begin{equation}
    \widehat{M}_k
    =
    \bigcup_{i\in\mathcal{C}_k} M_i.
    \label{eq:unija_maski_klastera}
\end{equation}

Ako su dostupne probabilističke maske \(p_i(\mathbf{x})\), mogu se koristiti
ponderisana agregacija i naknadno binarizovanje:
%
\begin{equation}
    \widehat{p}_k(\mathbf{x})
    =
    \frac{
        \sum_{i\in\mathcal{C}_k}
        w_i(\mathbf{x})p_i(\mathbf{x})
    }{
        \sum_{i\in\mathcal{C}_k}
        w_i(\mathbf{x})
        +\varepsilon
    },
    \label{eq:agregacija_probabilistickih_maski}
\end{equation}
%
\begin{equation}
    \widehat{M}_k(\mathbf{x})
    =
    \mathbb{I}
    \left[
        \widehat{p}_k(\mathbf{x})
        \geq
        \theta_m
    \right],
    \label{eq:binarizacija_konsolidovane_maske}
\end{equation}
%
gde težine \(w_i(\mathbf{x})\) mogu zavisiti od pouzdanosti predikcije i
udaljenosti piksela od granice izvorne pločice.

U ovom postupku IoA/IoM ne određuje geometriju konačne maske, već pouzdano
identifikuje koje parcijalne predikcije treba posmatrati kao jednu globalnu
instancu. Time izbor mere preklapanja direktno utiče na strukturu grafa
konsolidacije i konačan broj rekonstruisanih objekata.

\subsection{Zaključna razmatranja}
\label{subsec:zakljucak_iou_ioa}

IoU je simetrična mera obostrane sličnosti regiona i opravdano predstavlja
standard u evaluaciji detekcije, segmentacije i praćenja objekata. Njena
normalizacija unijom zahteva istovremeno veliko preklapanje i slične
površine regiona. Zbog toga IoU nije optimalna mera za sve faze obrade.

Kod tiled inferencije mala maska na granici pločice može predstavljati
ispravan, ali prostorno odsečen fragment objekta. Ako se poredi sa većom,
potpunijom maskom iste instance, IoU je ograničen odnosom njihovih površina.
Čak i savršeno sadržavanje fragmenta daje
%
\begin{equation}
    \operatorname{IoU}(S,L)
    =
    \frac{|S|}{|L|},
\end{equation}
%
što može biti proizvoljno mala vrednost.

IoA nad manjom maskom, odnosno njegova simetrična IoM/IoS varijanta,
normalizuje presek površinom fragmenta i direktno meri njegovu pokrivenost:
%
\begin{equation}
    \operatorname{IoM}(S,L)
    =
    \frac{|S\cap L|}{|S|}.
\end{equation}

Zbog nezavisnosti od odnosa površina, IoA/IoM je matematički primereniji za
odlučivanje da li mala, visoko odsečena maska i veća maska iz susedne
pločice predstavljaju istu instancu. Međutim, ovu meru treba primenjivati
kontekstualno, prvenstveno nad predikcijama iz susednih pločica i preklopnih
zona, uz uslov da najmanje jedna predikcija predstavlja kandidata presečenog
granicom pločice.

Stoga se za globalnu konsolidaciju maski preporučuje hibridni pristup:
IoU za duplirane predikcije sličnih površina, a IoA nad manjim kandidatom ili
IoM za asimetrične parove koji sadrže potencijalno odsečenu masku. Takva
podela uloga usklađuje matematička svojstva mera sa različitim tipovima
grešaka nastalim tokom tiled inferencije.
```

Primeri BibTeX zapisa za korišćene izvore:

```bibtex
@inproceedings{ronneberger2015unet,
  author    = {Ronneberger, Olaf and Fischer, Philipp and Brox, Thomas},
  title     = {{U-Net}: Convolutional Networks for Biomedical Image Segmentation},
  booktitle = {Medical Image Computing and Computer-Assisted Intervention},
  year      = {2015},
  pages     = {234--241},
  publisher = {Springer}
}

@article{majurski2021exact,
  author  = {Majurski, Michael and Bajcsy, Peter},
  title   = {Exact Tile-Based Segmentation Inference for Images Larger than GPU Memory},
  journal = {Journal of Research of the National Institute of Standards and Technology},
  volume  = {126},
  year    = {2021},
  doi     = {10.6028/jres.126.009}
}

@inproceedings{akyon2022sahi,
  author    = {Akyon, Fatih Cagatay and Altinuc, Sinan Onur and Temizel, Alptekin},
  title     = {Slicing Aided Hyper Inference and Fine-Tuning for Small Object Detection},
  booktitle = {IEEE International Conference on Image Processing},
  year      = {2022},
  pages     = {966--970},
  doi       = {10.1109/ICIP46576.2022.9897990}
}

@misc{sahiRepository,
  author       = {{OBSS}},
  title        = {{SAHI}: Slicing Aided Hyper Inference},
  howpublished = {\url{https://github.com/obss/sahi}},
  note         = {Pristupljeno: unesite datum pristupa}
}

@inproceedings{lin2014coco,
  author    = {Lin, Tsung-Yi and Maire, Michael and Belongie, Serge and
               Hays, James and Perona, Pietro and Ramanan, Deva and
               Doll{\'a}r, Piotr and Zitnick, C. Lawrence},
  title     = {Microsoft {COCO}: Common Objects in Context},
  booktitle = {European Conference on Computer Vision},
  year      = {2014},
  pages     = {740--755}
}

@misc{cocoapi,
  author       = {{COCO Consortium}},
  title        = {{COCO API}},
  howpublished = {\url{https://github.com/cocodataset/cocoapi}},
  note         = {Pristupljeno: unesite datum pristupa}
}

@inproceedings{wu2013tracking,
  author    = {Wu, Yi and Lim, Jongwoo and Yang, Ming-Hsuan},
  title     = {Online Object Tracking: A Benchmark},
  booktitle = {IEEE Conference on Computer Vision and Pattern Recognition},
  year      = {2013},
  pages     = {2411--2418}
}

@inproceedings{bewley2016sort,
  author    = {Bewley, Alex and Ge, Zongyuan and Ott, Lionel and
               Ramos, Fabio and Upcroft, Ben},
  title     = {Simple Online and Realtime Tracking},
  booktitle = {IEEE International Conference on Image Processing},
  year      = {2016},
  pages     = {3464--3468}
}

@article{everingham2010pascal,
  author  = {Everingham, Mark and Van Gool, Luc and Williams, Christopher K. I.
             and Winn, John and Zisserman, Andrew},
  title   = {The {PASCAL} Visual Object Classes Challenge},
  journal = {International Journal of Computer Vision},
  volume  = {88},
  number  = {2},
  pages   = {303--338},
  year    = {2010}
}
```
:::

Grafik koristi standardni `pgfplots` i prikazuje ključni teorijski rezultat: za potpuno sadržavanje važi \(\mathrm{IoU}=\tau\), dok IoA ostaje jednak jedinici. Terminologija je namerno postavljena tako da se jasno razlikuju usmereni \(\operatorname{IoA}_{A}\) i simetrični \(\operatorname{IoM}\), pošto se naziv IoA u postojećim radovima i bibliotekama ne koristi potpuno jednoznačno.
