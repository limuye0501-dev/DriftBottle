import SwiftUI

/// App Store 截图专用模式：仅 DEBUG 构建，且仅当启动参数 `-DBScreenshot <scene>` 存在时启用。
/// Release（TestFlight / App Store）构建中 `Demo.scene` 恒为 nil，不含任何样例数据。
enum Demo {
    #if DEBUG
    static let scene: String? = UserDefaults.standard.string(forKey: "DBScreenshot")
    #else
    static let scene: String? = nil
    #endif
    static var on: Bool { scene != nil }
}

#if DEBUG
extension Demo {
    static let me = "demo-me", other = "demo-other"
    static var lang: String { AppLocale.code }

    /// 价格取自 App Store Connect 对应店面（月 / 年）
    private static let prices: [String: (String, Decimal, Decimal)] = [
        "en": ("USD", 1.99, 9.99), "ja": ("JPY", 300, 1500), "ko": ("KRW", 3300, 17000), "zh-Hans": ("CNY", 15, 68),
        "zh-Hant": ("TWD", 60, 320), "es": ("EUR", 1.99, 9.99), "fr": ("EUR", 1.99, 9.99), "de": ("EUR", 1.99, 9.99),
        "it": ("EUR", 1.99, 9.99), "pt-BR": ("BRL", 12.9, 59.9), "ru": ("RUB", 199, 899), "th": ("THB", 79, 399),
        "vi": ("VND", 59000, 299000), "id": ("IDR", 39000, 199000), "tr": ("TRY", 99.99, 499.99), "ar": ("SAR", 9.99, 39.99),
    ]
    private static func fmt(_ v: Decimal) -> String {
        let p = prices[lang] ?? prices["en"]!
        return v.formatted(.currency(code: p.0).locale(Locale.current))
    }
    static func price(_ t: MemberTier) -> String {
        let p = prices[lang] ?? prices["en"]!
        return t == .monthly ? fmt(p.1) : t == .annual ? fmt(p.2) : "—"
    }
    static var annualPerMonth: String { fmt((prices[lang] ?? prices["en"]!).2 / 12) }

    struct Copy { let letter: String; let compose: String; let reply: String; let chat: [String]; let mine: [String] }
    static var copy: Copy { copies[lang] ?? copies["en"]! }
    static let copies: [String: Copy] = [
        "en": Copy(letter: "The sea was calm tonight and I couldn't sleep, so I'm writing to whoever finds this. Tell me one small thing that made you smile today?",
                   compose: "Dear stranger, I just moved to a new city by the sea. Every evening I walk along the shore and wonder who else is watching the same sunset…",
                   reply: "Hi! A stray cat followed me home today 🐈",
                   chat: ["Hi! A stray cat followed me home today 🐈", "That's adorable! Did you give it a name?", "Not yet. Any ideas?", "How about \"Tide\"? It found you, like this bottle 🌊"],
                   mine: ["Dear stranger, I just moved to a new city by the sea…", "What song are you listening to right now?", "Today I finally finished my first painting."]),
        "zh-Hans": Copy(letter: "今晚海很安静，我睡不着，就写给捡到这只瓶子的你。今天有什么小事让你笑了吗？",
                   compose: "陌生人你好，我刚搬到一座海边的城市。每天傍晚沿着海边散步，总在想还有谁和我看着同一片晚霞……",
                   reply: "你好呀！今天有只流浪猫一路跟我回家 🐈",
                   chat: ["你好呀！今天有只流浪猫一路跟我回家 🐈", "好可爱！给它起名字了吗？", "还没有，你有什么好主意？", "叫“潮汐”怎么样？它找到了你，就像这只瓶子 🌊"],
                   mine: ["陌生人你好，我刚搬到一座海边的城市……", "你现在在听什么歌？", "今天终于画完了人生第一幅画。"]),
        "zh-Hant": Copy(letter: "今晚海很安靜，我睡不著，就寫給撿到這隻瓶子的你。今天有什麼小事讓你笑了嗎？",
                   compose: "陌生人你好，我剛搬到一座海邊的城市。每天傍晚沿著海邊散步，總在想還有誰和我看著同一片晚霞……",
                   reply: "你好呀！今天有隻流浪貓一路跟我回家 🐈",
                   chat: ["你好呀！今天有隻流浪貓一路跟我回家 🐈", "好可愛！幫牠取名字了嗎？", "還沒有，你有什麼好點子？", "叫「潮汐」怎麼樣？牠找到了你，就像這隻瓶子 🌊"],
                   mine: ["陌生人你好，我剛搬到一座海邊的城市……", "你現在在聽什麼歌？", "今天終於畫完了人生第一幅畫。"]),
        "ja": Copy(letter: "今夜の海はとても静かで眠れないので、このボトルを拾ったあなたに書いています。今日、思わず笑顔になった小さなことを教えてくれませんか？",
                   compose: "見知らぬあなたへ。海辺の街に引っ越してきたばかりです。毎晩浜辺を歩きながら、同じ夕焼けを見ている人がいるのかなと考えています…",
                   reply: "こんにちは！今日、野良猫が家までついてきました 🐈",
                   chat: ["こんにちは！今日、野良猫が家までついてきました 🐈", "かわいい！名前はつけましたか？", "まだです。何かいい案ある？", "「しお」はどう？このボトルみたいに、あなたを見つけてくれたから 🌊"],
                   mine: ["見知らぬあなたへ。海辺の街に引っ越してきたばかりです…", "今、どんな曲を聴いていますか？", "今日、初めての絵を描き上げました。"]),
        "ko": Copy(letter: "오늘 밤 바다가 너무 고요해서 잠이 안 와요. 이 유리병을 주운 당신에게 써요. 오늘 당신을 웃게 한 작은 일 하나만 알려 줄래요?",
                   compose: "모르는 당신에게, 바닷가 도시로 막 이사 왔어요. 매일 저녁 해변을 걸으며 누가 같은 노을을 보고 있을까 생각해요…",
                   reply: "안녕하세요! 오늘 길고양이가 집까지 따라왔어요 🐈",
                   chat: ["안녕하세요! 오늘 길고양이가 집까지 따라왔어요 🐈", "너무 귀엽네요! 이름 지어 줬어요?", "아직이요. 좋은 생각 있어요?", "‘파도’ 어때요? 이 유리병처럼 당신을 찾아왔잖아요 🌊"],
                   mine: ["모르는 당신에게, 바닷가 도시로 막 이사 왔어요…", "지금 무슨 노래 듣고 있어요?", "오늘 드디어 첫 그림을 완성했어요."]),
        "es": Copy(letter: "Esta noche el mar estaba en calma y no podía dormir, así que le escribo a quien encuentre esto. ¿Me cuentas algo pequeño que te hizo sonreír hoy?",
                   compose: "Querido desconocido: acabo de mudarme a una ciudad junto al mar. Cada tarde paseo por la orilla y me pregunto quién más estará mirando el mismo atardecer…",
                   reply: "¡Hola! Hoy un gato callejero me siguió hasta casa 🐈",
                   chat: ["¡Hola! Hoy un gato callejero me siguió hasta casa 🐈", "¡Qué tierno! ¿Le pusiste nombre?", "Todavía no. ¿Alguna idea?", "¿Qué tal «Marea»? Te encontró, como esta botella 🌊"],
                   mine: ["Querido desconocido: acabo de mudarme a una ciudad junto al mar…", "¿Qué canción estás escuchando ahora?", "Hoy por fin terminé mi primer cuadro."]),
        "fr": Copy(letter: "La mer était calme ce soir et je n'arrivais pas à dormir, alors j'écris à la personne qui trouvera ceci. Tu me racontes une petite chose qui t'a fait sourire aujourd'hui ?",
                   compose: "Cher inconnu, je viens d'emménager dans une ville au bord de la mer. Chaque soir je marche sur la plage en me demandant qui regarde le même coucher de soleil…",
                   reply: "Salut ! Un chat errant m'a suivi jusqu'à chez moi aujourd'hui 🐈",
                   chat: ["Salut ! Un chat errant m'a suivi jusqu'à chez moi aujourd'hui 🐈", "Trop mignon ! Tu lui as donné un nom ?", "Pas encore. Une idée ?", "Pourquoi pas « Marée » ? Il t'a trouvé, comme cette bouteille 🌊"],
                   mine: ["Cher inconnu, je viens d'emménager dans une ville au bord de la mer…", "Quelle chanson écoutes-tu en ce moment ?", "J'ai enfin terminé mon premier tableau."]),
        "de": Copy(letter: "Das Meer war heute Nacht ganz ruhig und ich konnte nicht schlafen, also schreibe ich dir, wer immer das findet. Erzählst du mir eine Kleinigkeit, die dich heute zum Lächeln gebracht hat?",
                   compose: "Liebe:r Unbekannte:r, ich bin gerade in eine Stadt am Meer gezogen. Jeden Abend gehe ich am Strand spazieren und frage mich, wer wohl denselben Sonnenuntergang sieht …",
                   reply: "Hallo! Heute ist mir eine streunende Katze bis nach Hause gefolgt 🐈",
                   chat: ["Hallo! Heute ist mir eine streunende Katze bis nach Hause gefolgt 🐈", "Wie süß! Hast du ihr einen Namen gegeben?", "Noch nicht. Hast du eine Idee?", "Wie wäre es mit „Flut“? Sie hat dich gefunden – wie diese Flasche 🌊"],
                   mine: ["Liebe:r Unbekannte:r, ich bin gerade in eine Stadt am Meer gezogen …", "Welchen Song hörst du gerade?", "Heute habe ich endlich mein erstes Bild fertig gemalt."]),
        "pt-BR": Copy(letter: "O mar estava calmo hoje à noite e eu não conseguia dormir, então escrevo para quem encontrar isto. Me conta uma coisinha que te fez sorrir hoje?",
                   compose: "Querido desconhecido, acabei de me mudar para uma cidade à beira-mar. Toda tarde caminho pela praia e me pergunto quem mais está vendo o mesmo pôr do sol…",
                   reply: "Oi! Hoje um gatinho de rua me seguiu até em casa 🐈",
                   chat: ["Oi! Hoje um gatinho de rua me seguiu até em casa 🐈", "Que fofo! Você deu um nome pra ele?", "Ainda não. Alguma ideia?", "Que tal \"Maré\"? Ele te encontrou, como esta garrafa 🌊"],
                   mine: ["Querido desconhecido, acabei de me mudar para uma cidade à beira-mar…", "Que música você está ouvindo agora?", "Hoje finalmente terminei minha primeira pintura."]),
        "it": Copy(letter: "Stanotte il mare era calmo e non riuscivo a dormire, così scrivo a chi troverà questo messaggio. Mi racconti una piccola cosa che oggi ti ha fatto sorridere?",
                   compose: "Caro sconosciuto, mi sono appena trasferito in una città sul mare. Ogni sera cammino sulla riva e mi chiedo chi altro stia guardando lo stesso tramonto…",
                   reply: "Ciao! Oggi un gatto randagio mi ha seguito fino a casa 🐈",
                   chat: ["Ciao! Oggi un gatto randagio mi ha seguito fino a casa 🐈", "Che tenero! Gli hai dato un nome?", "Non ancora. Qualche idea?", "Che ne dici di «Marea»? Ti ha trovato, come questa bottiglia 🌊"],
                   mine: ["Caro sconosciuto, mi sono appena trasferito in una città sul mare…", "Che canzone stai ascoltando adesso?", "Oggi ho finalmente finito il mio primo quadro."]),
        "ru": Copy(letter: "Сегодня ночью море было спокойным, а мне не спалось, поэтому пишу тому, кто найдёт это письмо. Расскажешь, какая мелочь сегодня заставила тебя улыбнуться?",
                   compose: "Привет, незнакомец! Я только что переехал в город у моря. Каждый вечер гуляю по берегу и думаю, кто ещё смотрит на тот же закат…",
                   reply: "Привет! Сегодня за мной до дома шёл бездомный кот 🐈",
                   chat: ["Привет! Сегодня за мной до дома шёл бездомный кот 🐈", "Как мило! Ты дал ему имя?", "Пока нет. Есть идеи?", "Может, «Прилив»? Он нашёл тебя, как эта бутылка 🌊"],
                   mine: ["Привет, незнакомец! Я только что переехал в город у моря…", "Какую песню ты сейчас слушаешь?", "Сегодня я наконец дорисовал свою первую картину."]),
        "th": Copy(letter: "คืนนี้ทะเลเงียบมากจนนอนไม่หลับ เลยเขียนถึงใครก็ตามที่เก็บขวดนี้ได้ วันนี้มีเรื่องเล็ก ๆ อะไรที่ทำให้คุณยิ้มบ้างไหม?",
                   compose: "ถึงคนแปลกหน้า ฉันเพิ่งย้ายมาอยู่เมืองริมทะเล ทุกเย็นฉันเดินเล่นริมหาดและสงสัยว่าใครอีกบ้างที่กำลังมองพระอาทิตย์ตกดวงเดียวกัน…",
                   reply: "สวัสดี! วันนี้มีแมวจรเดินตามฉันกลับบ้าน 🐈",
                   chat: ["สวัสดี! วันนี้มีแมวจรเดินตามฉันกลับบ้าน 🐈", "น่ารักจัง! ตั้งชื่อให้มันหรือยัง?", "ยังเลย มีไอเดียไหม?", "ชื่อ \"คลื่น\" ดีไหม? มันหาคุณเจอ เหมือนขวดนี้ 🌊"],
                   mine: ["ถึงคนแปลกหน้า ฉันเพิ่งย้ายมาอยู่เมืองริมทะเล…", "ตอนนี้คุณฟังเพลงอะไรอยู่?", "วันนี้วาดรูปแรกในชีวิตเสร็จแล้ว"]),
        "vi": Copy(letter: "Đêm nay biển thật yên, mình không ngủ được nên viết cho ai nhặt được chai này. Kể mình nghe một điều nhỏ khiến bạn mỉm cười hôm nay nhé?",
                   compose: "Gửi người lạ, mình vừa chuyển đến một thành phố ven biển. Mỗi chiều mình dạo dọc bờ biển và tự hỏi còn ai đang ngắm cùng một hoàng hôn…",
                   reply: "Chào bạn! Hôm nay có một chú mèo hoang theo mình về tận nhà 🐈",
                   chat: ["Chào bạn! Hôm nay có một chú mèo hoang theo mình về tận nhà 🐈", "Dễ thương quá! Bạn đặt tên cho nó chưa?", "Chưa nữa. Bạn có ý tưởng gì không?", "Gọi là \"Sóng\" nhé? Nó tìm thấy bạn, như chiếc chai này 🌊"],
                   mine: ["Gửi người lạ, mình vừa chuyển đến một thành phố ven biển…", "Bạn đang nghe bài hát gì vậy?", "Hôm nay mình đã vẽ xong bức tranh đầu tiên."]),
        "id": Copy(letter: "Malam ini laut begitu tenang dan aku tidak bisa tidur, jadi aku menulis untuk siapa pun yang menemukan ini. Ceritakan satu hal kecil yang membuatmu tersenyum hari ini?",
                   compose: "Untuk orang asing, aku baru pindah ke kota di tepi laut. Setiap sore aku berjalan di pantai dan bertanya-tanya siapa lagi yang melihat senja yang sama…",
                   reply: "Hai! Hari ini ada kucing liar yang mengikutiku sampai rumah 🐈",
                   chat: ["Hai! Hari ini ada kucing liar yang mengikutiku sampai rumah 🐈", "Lucu banget! Sudah kamu beri nama?", "Belum. Ada ide?", "Bagaimana kalau \"Ombak\"? Dia menemukanmu, seperti botol ini 🌊"],
                   mine: ["Untuk orang asing, aku baru pindah ke kota di tepi laut…", "Lagu apa yang sedang kamu dengarkan?", "Hari ini akhirnya aku menyelesaikan lukisan pertamaku."]),
        "tr": Copy(letter: "Bu gece deniz çok sakindi ve uyuyamadım, bu yüzden bunu bulan kişiye yazıyorum. Bugün seni gülümseten küçük bir şeyi anlatır mısın?",
                   compose: "Sevgili yabancı, deniz kenarındaki bir şehre yeni taşındım. Her akşam sahilde yürüyüp aynı gün batımını başka kimlerin izlediğini merak ediyorum…",
                   reply: "Merhaba! Bugün sokak kedisi beni eve kadar takip etti 🐈",
                   chat: ["Merhaba! Bugün sokak kedisi beni eve kadar takip etti 🐈", "Çok tatlı! Ona bir isim verdin mi?", "Henüz değil. Bir fikrin var mı?", "\"Dalga\" nasıl? Bu şişe gibi seni buldu 🌊"],
                   mine: ["Sevgili yabancı, deniz kenarındaki bir şehre yeni taşındım…", "Şu an hangi şarkıyı dinliyorsun?", "Bugün sonunda ilk resmimi bitirdim."]),
        "ar": Copy(letter: "كان البحر هادئًا الليلة ولم أستطع النوم، لذا أكتب لمن يجد هذه الرسالة. هل تخبرني بشيء صغير جعلك تبتسم اليوم؟",
                   compose: "عزيزي الغريب، انتقلت للتو إلى مدينة على البحر. كل مساء أمشي على الشاطئ وأتساءل من غيري يشاهد الغروب نفسه…",
                   reply: "مرحبًا! تبعتني قطة شاردة إلى البيت اليوم 🐈",
                   chat: ["مرحبًا! تبعتني قطة شاردة إلى البيت اليوم 🐈", "يا لها من لطيفة! هل أطلقت عليها اسمًا؟", "ليس بعد. هل لديك فكرة؟", "ما رأيك بـ«موجة»؟ لقد وجدتك مثل هذه الزجاجة 🌊"],
                   mine: ["عزيزي الغريب، انتقلت للتو إلى مدينة على البحر…", "ما الأغنية التي تستمع إليها الآن؟", "أنهيت اليوم أخيرًا أول لوحة لي."]),
    ]

    static var profile: UserProfile {
        UserProfile(id: me, nickname: L("nickname.format", 2718), gender: .female, age: 27, birthYear: Calendar.current.component(.year, from: .now) - 27)
    }
    static var letter: Bottle {
        Bottle(id: "demo-letter", senderId: other, senderNickname: L("nickname.format", 4721), senderGender: .male,
               senderBirthYear: Calendar.current.component(.year, from: .now) - 29, text: copy.letter, style: "moonlight",
               status: .viewed, createdAt: Date().addingTimeInterval(-2 * 86400))
    }
    static var myBottles: [Bottle] {
        let s: [(String, BottleStatus, [String], Double)] = [("amber", .replied, [other, "x"], 3600), ("classic", .kept, [], 86400 * 2), ("sakura", .floating, [], 86400 * 5)]
        return zip(copy.mine, s).enumerated().map { i, p in
            Bottle(id: "demo-mine-\(i)", senderId: me, senderNickname: profile.nickname, senderGender: .female, senderBirthYear: profile.birthYear,
                   text: p.0, style: p.1.0, status: p.1.1, replierIds: p.1.2, createdAt: Date().addingTimeInterval(-p.1.3))
        }
    }
    static var chat: Chat {
        Chat(id: "demo-chat", participants: [me, other], bottleId: "demo-mine-0", lastMessage: copy.chat.last ?? "",
             names: [other: L("nickname.format", 4721), me: profile.nickname], updatedAt: Date())
    }
    static var chats: [Chat] {
        [chat, Chat(id: "demo-chat-2", participants: [me, "demo-3"], bottleId: "demo-mine-1", lastMessage: copy.reply,
                    names: ["demo-3": L("nickname.format", 1530)], updatedAt: Date().addingTimeInterval(-7200))]
    }
    static var messages: [ChatMessage] {
        var list = [ChatMessage(id: "o", senderId: me, text: copy.mine[0], kind: "origin", createdAt: Date().addingTimeInterval(-4000))]
        for (i, t) in copy.chat.enumerated() {
            list.append(ChatMessage(id: "m\(i)", senderId: i % 2 == 0 ? other : me, text: t, createdAt: Date().addingTimeInterval(Double(-3000 + i * 300))))
        }
        return list
    }
}

/// 截图场景：home / compose / letter / chats / chat / bottles / paywall
struct DemoRootView: View {
    var body: some View {
        switch Demo.scene {
        case "compose": ThrowComposerView { _ in }
        case "letter": LetterView(bottle: Demo.letter)
        case "chat": NavigationStack { ChatView(chat: Demo.chat) }
        case "paywall": PaywallView()
        case "chats": MainTabView(initialTab: 1)
        case "bottles": MainTabView(initialTab: 2)
        default: MainTabView()
        }
    }
}
#endif
