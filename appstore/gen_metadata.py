#!/usr/bin/env python3
"""Writes appstore/metadata/<locale>/{name,subtitle,keywords,description,promotional_text}.txt (fastlane deliver layout).
Positioning: a calm pastime for business travelers on quiet hotel nights. Not dating/social."""
import os
M = {
"zh-Hans": ("漂流瓶 · 夜海来信", "出差夜里，给大海写几行字", "出差,酒店,失眠,深夜,解闷,打发时间,写信,树洞,匿名,治愈,放松,大海,夜晚,信件,手写,海浪,白噪音",
 "出差在外，酒店房间安静得只剩空调声？\n把想说的话写进一只玻璃瓶，扔进今夜的海里；再捡起一只别人漂来的瓶子，读一读陌生旅人的一天。",
 ["无需注册：不要手机号、不要邮箱，打开就能写","每天免费扔 3 个、捡 3 个瓶子；回信、聊天、发图永远免费","精心打磨的动画：瓶子随浪起伏、软木塞“啵”的一声、夜空随时间变化","手写、楷体、打字机等字体和三种字号任你选，所有瓶子样式与信纸免费","内容审核、举报与拉黑，安静不被打扰"],
 "这不是社交软件，只是一个睡前的小消遣。仅限 18 岁及以上。会员价格以 App Store 显示为准。"),
"en-US": ("Drift Bottle: Night Sea Notes", "Quiet notes for hotel nights", "hotel,travel,insomnia,night,boredom,pastime,letter,anonymous,calm,relax,ocean,waves,journal,message",
 "On the road for work and the hotel room is too quiet?\nWrite a few lines, seal them in a glass bottle and toss it into tonight's sea. Then pick up a bottle someone else set adrift and read a stranger's day.",
 ["No sign-up: no phone number, no email — just open and write","3 free throws and 3 free picks every day; replies, chat and photos are always free","Hand-crafted animations: bobbing bottles, a satisfying cork pop, a sky that follows the clock","Pick a handwriting, Kai or typewriter font in three sizes; every bottle style and letter paper is free","Moderation, reporting and blocking keep things calm"],
 "Not a social network — just a small pastime before sleep. 18+ only. Membership prices are shown in the App Store."),
"zh-Hant": ("漂流瓶 · 夜海來信", "出差夜裡，給大海寫幾行字", "出差,飯店,失眠,深夜,解悶,打發時間,寫信,樹洞,匿名,療癒,放鬆,大海,夜晚,信件,海浪,白噪音",
 "出差在外，飯店房間安靜得只剩冷氣聲？\n把想說的話寫進一只玻璃瓶，丟進今夜的海裡；再撿起一只別人漂來的瓶子，讀一讀陌生旅人的一天。",
 ["免註冊：不用手機號碼、不用電子郵件，打開就能寫","每天免費丟 3 個、撿 3 個瓶子；回信、聊天、傳照片永遠免費","細緻動畫：瓶子隨浪起伏、軟木塞「啵」的一聲、夜空隨時間變化","手寫、楷體、打字機等字體和三種字號任你選，所有瓶子樣式與信紙免費","內容審核、檢舉與封鎖，安靜不被打擾"],
 "這不是社群軟體，只是睡前的小消遣。限 18 歲以上使用。會員價格以 App Store 顯示為準。"),
"ja": ("ボトルメール：夜の海の手紙", "出張の夜、海に数行の手紙を", "出張,ホテル,眠れない,夜,暇つぶし,手紙,匿名,癒し,リラックス,海,波,日記,メッセージ,一人時間",
 "出張先のホテル、静かすぎて眠れない夜に。\n思ったことを数行ガラス瓶に入れて、今夜の海へ流してみませんか。誰かが流した瓶を拾えば、知らない旅人の一日が読めます。",
 ["登録不要：電話番号もメールアドレスもいりません","毎日 3 回流せて 3 回拾えます。返信・チャット・写真はいつでも無料","こだわりのアニメーション：波に揺れる瓶、コルクの「ポン」、時刻に合わせて変わる夜空","手書き・楷書・タイプライターなどのフォントと 3 つの文字サイズ。ボトルと便箋はすべて無料","審査・通報・ブロックで穏やかな空間を"],
 "出会い系ではありません。眠る前のささやかな暇つぶしです。18 歳以上対象。料金は App Store の表示をご確認ください。"),
"ko": ("유리병 편지: 밤바다 편지", "출장의 밤, 바다에 몇 줄 적어요", "출장,호텔,불면,밤,심심,시간때우기,편지,익명,힐링,휴식,바다,파도,일기,메시지,혼자",
 "출장지 호텔 방이 너무 조용한 밤인가요?\n하고 싶은 말을 몇 줄 적어 유리병에 담아 오늘 밤 바다에 띄워 보세요. 누군가 띄운 병을 주우면 낯선 여행자의 하루를 읽을 수 있어요.",
 ["가입 불필요: 전화번호도 이메일도 필요 없어요","매일 무료로 3번 띄우고 3번 줍기. 답장·채팅·사진은 언제나 무료","정성 들인 애니메이션: 파도에 흔들리는 병, 코르크 '뽕' 소리, 시간에 따라 바뀌는 밤하늘","손글씨·해서체·타자기 글꼴과 세 가지 글자 크기, 모든 병 스타일과 편지지는 무료","검토·신고·차단으로 조용하고 편안하게"],
 "소개팅 앱이 아니에요. 잠들기 전 소소한 시간 보내기예요. 만 18세 이상. 가격은 App Store에 표시된 금액을 확인하세요."),
"es-ES": ("Botella al Mar: mar de noche", "Notas para noches de hotel", "hotel,viaje,insomnio,noche,aburrimiento,pasatiempo,carta,anónimo,calma,relax,océano,olas,diario,mensaje",
 "¿De viaje de trabajo y la habitación del hotel está demasiado silenciosa?\nEscribe unas líneas, guárdalas en una botella y lánzala al mar de esta noche. Luego recoge la botella de otra persona y lee el día de un desconocido.",
 ["Sin registro: ni teléfono ni correo, abre y escribe","3 lanzamientos y 3 recogidas gratis al día; responder, chatear y enviar fotos siempre es gratis","Animaciones cuidadas: botellas que se mecen, el «pop» del corcho, un cielo que sigue la hora","Elige letra manuscrita, Kai o de máquina de escribir en tres tamaños; todos los estilos y papeles son gratis","Moderación, denuncias y bloqueo para que todo siga en calma"],
 "No es una app de citas ni una red social: solo un pasatiempo antes de dormir. Solo +18. Los precios aparecen en la App Store."),
"fr-FR": ("Bouteille à la mer : la nuit", "Quelques mots, un soir d'hôtel", "hôtel,voyage,insomnie,nuit,ennui,passe-temps,lettre,anonyme,calme,détente,océan,vagues,journal,message",
 "En déplacement et la chambre d'hôtel est trop silencieuse ?\nÉcrivez quelques lignes, glissez-les dans une bouteille et confiez-la à la mer de ce soir. Puis repêchez celle d'un autre et lisez la journée d'un inconnu.",
 ["Sans inscription : ni numéro, ni e-mail, ouvrez et écrivez","3 lancers et 3 repêchages gratuits par jour ; répondre, discuter et envoyer des photos reste toujours gratuit","Animations soignées : bouteilles bercées par la houle, « pop » du bouchon, ciel qui suit l'heure","Police manuscrite, Kai ou machine à écrire, en trois tailles ; tous les styles et papiers sont gratuits","Modération, signalement et blocage pour rester serein"],
 "Ce n'est ni une appli de rencontre ni un réseau social : juste un passe-temps avant de dormir. Réservé aux 18 ans et plus. Les prix sont indiqués dans l'App Store."),
"de-DE": ("Flaschenpost: Nachtmeer", "Zeilen für stille Hotelnächte", "Hotel,Reise,Dienstreise,schlaflos,Nacht,Langeweile,Zeitvertreib,Brief,anonym,Ruhe,Meer,Wellen,Tagebuch",
 "Auf Dienstreise und das Hotelzimmer ist viel zu still?\nSchreib ein paar Zeilen, steck sie in eine Glasflasche und übergib sie dem Meer von heute Nacht. Dann fisch die Flasche eines anderen heraus und lies vom Tag eines Fremden.",
 ["Keine Registrierung: keine Telefonnummer, keine E-Mail – öffnen und schreiben","Täglich 3 Flaschen werfen und 3 auffischen, kostenlos; Antworten, Chat und Fotos sind immer gratis","Liebevolle Animationen: schaukelnde Flaschen, das „Plopp“ des Korkens, ein Himmel, der der Uhrzeit folgt","Handschrift, Kai oder Schreibmaschine in drei Größen; alle Flaschenstile und Briefpapiere sind gratis","Moderation, Melden und Blockieren sorgen für Ruhe"],
 "Keine Dating-App und kein soziales Netzwerk – nur ein kleiner Zeitvertreib vor dem Schlafen. Ab 18. Preise siehe App Store."),
"pt-BR": ("Garrafa ao Mar: noite", "Bilhetes para noites de hotel", "hotel,viagem,insônia,noite,tédio,passatempo,carta,anônimo,calma,relaxar,oceano,ondas,diário,mensagem",
 "Viajando a trabalho e o quarto do hotel está quieto demais?\nEscreva algumas linhas, coloque numa garrafa e jogue no mar desta noite. Depois pesque a garrafa de outra pessoa e leia o dia de um desconhecido.",
 ["Sem cadastro: sem telefone, sem e-mail, é só abrir e escrever","3 lançamentos e 3 pescas grátis por dia; responder, conversar e enviar fotos é sempre grátis","Animações caprichadas: garrafas balançando, o “pop” da rolha, um céu que acompanha o horário","Escolha letra manuscrita, Kai ou de máquina de escrever em três tamanhos; todos os estilos e papéis são grátis","Moderação, denúncia e bloqueio para manter tudo tranquilo"],
 "Não é app de namoro nem rede social: só um passatempo antes de dormir. Apenas maiores de 18. Preços exibidos na App Store."),
"it": ("Messaggio in Bottiglia: notte", "Due righe per notti in hotel", "hotel,viaggio,insonnia,notte,noia,passatempo,lettera,anonimo,calma,relax,oceano,onde,diario,messaggio",
 "In trasferta e la camera d'albergo è troppo silenziosa?\nScrivi qualche riga, chiudila in una bottiglia e affidala al mare di stanotte. Poi ripesca la bottiglia di qualcun altro e leggi la giornata di uno sconosciuto.",
 ["Nessuna registrazione: niente numero, niente e-mail, apri e scrivi","3 lanci e 3 ripescaggi gratis al giorno; rispondere, chattare e inviare foto è sempre gratis","Animazioni curate: bottiglie cullate dalle onde, il “pop” del tappo, un cielo che segue l'ora","Carattere corsivo, Kai o macchina da scrivere in tre dimensioni; tutti gli stili e le carte sono gratis","Moderazione, segnalazioni e blocco per restare tranquilli"],
 "Non è un'app di incontri né un social: solo un passatempo prima di dormire. Solo maggiorenni. Prezzi indicati nell'App Store."),
"ru": ("Письмо в бутылке: ночное море", "Пара строк для ночи в отеле", "отель,командировка,бессонница,ночь,скука,досуг,письмо,анонимно,спокойствие,море,волны,дневник",
 "В командировке, а в номере отеля слишком тихо?\nНапишите пару строк, запечатайте в бутылку и отпустите в сегодняшнее море. А потом выловите чужую бутылку и прочитайте о дне незнакомого путника.",
 ["Без регистрации: ни телефона, ни почты — просто откройте и пишите","Каждый день бесплатно 3 броска и 3 улова; ответы, чат и фото всегда бесплатны","Продуманная анимация: бутылки качаются на волнах, пробка хлопает, небо меняется вместе со временем","Рукописный шрифт, Кай или пишущая машинка в трёх размерах; все стили бутылок и бумаги бесплатны","Модерация, жалобы и блокировка берегут спокойствие"],
 "Это не приложение для знакомств и не соцсеть — просто тихое занятие перед сном. Только 18+. Цены указаны в App Store."),
"th": ("จดหมายในขวด: ทะเลยามค่ำ", "เขียนสักบรรทัดในคืนที่โรงแรม", "โรงแรม,เดินทาง,นอนไม่หลับ,กลางคืน,เบื่อ,ฆ่าเวลา,จดหมาย,นิรนาม,ผ่อนคลาย,ทะเล,คลื่น,ไดอารี่",
 "เดินทางไปทำงาน แล้วห้องโรงแรมเงียบเกินไปใช่ไหม?\nเขียนสักไม่กี่บรรทัดใส่ขวดแก้ว แล้วปล่อยลงทะเลคืนนี้ จากนั้นลองเก็บขวดของคนอื่นขึ้นมาอ่านเรื่องราวในวันหนึ่งของนักเดินทางแปลกหน้า",
 ["ไม่ต้องสมัคร: ไม่ต้องใช้เบอร์โทรหรืออีเมล เปิดแล้วเขียนได้เลย","โยนฟรี 3 ครั้งและเก็บฟรี 3 ครั้งทุกวัน ตอบกลับ แชต และส่งรูปฟรีเสมอ","แอนิเมชันประณีต: ขวดลอยตามคลื่น เสียงจุกก๊อก “ป๊อก” ท้องฟ้าเปลี่ยนตามเวลา","เลือกฟอนต์ลายมือ ไข่ หรือเครื่องพิมพ์ดีด ได้ 3 ขนาด ขวดและกระดาษจดหมายทุกแบบใช้ฟรี","มีการตรวจสอบเนื้อหา รายงาน และบล็อก ให้คุณสบายใจ"],
 "ไม่ใช่แอปหาคู่หรือโซเชียล เป็นแค่กิจกรรมเล็ก ๆ ก่อนนอน สำหรับผู้มีอายุ 18 ปีขึ้นไป ราคาดูได้ใน App Store"),
"vi": ("Thư trong chai: biển đêm", "Vài dòng cho đêm ở khách sạn", "khách sạn,công tác,mất ngủ,đêm,buồn chán,giải trí,thư,ẩn danh,thư giãn,biển,sóng,nhật ký",
 "Đi công tác và phòng khách sạn quá yên tĩnh?\nViết vài dòng, cho vào chai thủy tinh và thả xuống biển đêm nay. Rồi vớt chai của ai đó và đọc một ngày của người lữ khách xa lạ.",
 ["Không cần đăng ký: không số điện thoại, không email, mở là viết","Mỗi ngày miễn phí 3 lần thả và 3 lần vớt; trả lời, trò chuyện, gửi ảnh luôn miễn phí","Hoạt ảnh chăm chút: chai dập dềnh theo sóng, tiếng nút bần “bốp”, bầu trời đổi theo giờ","Chọn phông viết tay, Khải hoặc máy đánh chữ với ba cỡ chữ; mọi kiểu chai và giấy viết thư đều miễn phí","Kiểm duyệt, báo cáo và chặn giúp bạn yên tâm"],
 "Đây không phải ứng dụng hẹn hò hay mạng xã hội, chỉ là thú tiêu khiển nhỏ trước khi ngủ. Chỉ dành cho người từ 18 tuổi. Giá hiển thị trên App Store."),
"id": ("Pesan dalam Botol: Laut Malam", "Sebaris pesan di malam hotel", "hotel,dinas,perjalanan,insomnia,malam,bosan,iseng,surat,anonim,santai,laut,ombak,jurnal,pesan",
 "Sedang dinas luar kota dan kamar hotel terlalu sepi?\nTulis beberapa baris, masukkan ke botol kaca, lalu titipkan pada laut malam ini. Kemudian pungut botol milik orang lain dan baca sepotong hari seorang pelancong asing.",
 ["Tanpa daftar: tanpa nomor HP, tanpa email, buka lalu tulis","Gratis lempar 3 kali dan pungut 3 kali setiap hari; membalas, mengobrol, dan kirim foto selalu gratis","Animasi yang digarap teliti: botol terayun ombak, bunyi “pop” gabus, langit yang mengikuti jam","Pilih huruf tulisan tangan, Kai, atau mesin tik dalam tiga ukuran; semua gaya botol dan kertas gratis","Moderasi, laporan, dan blokir menjaga suasana tetap tenang"],
 "Bukan aplikasi kencan atau media sosial, hanya hiburan kecil sebelum tidur. Khusus 18+. Harga tertera di App Store."),
"tr": ("Şişedeki Mektup: Gece Denizi", "Otel gecelerine birkaç satır", "otel,iş seyahati,uykusuzluk,gece,can sıkıntısı,eğlence,mektup,anonim,sakin,deniz,dalga,günlük,mesaj",
 "İş seyahatindesin ve otel odası fazla mı sessiz?\nBirkaç satır yaz, bir cam şişeye koy ve bu gecenin denizine bırak. Sonra bir başkasının şişesini topla ve tanımadığın bir yolcunun gününü oku.",
 ["Kayıt yok: telefon numarası yok, e-posta yok; aç ve yaz","Her gün ücretsiz 3 atma ve 3 toplama; yanıt, sohbet ve fotoğraf her zaman ücretsiz","Özenli animasyonlar: dalgalarla sallanan şişeler, mantarın “pop” sesi, saate göre değişen gökyüzü","El yazısı, Kai veya daktilo yazı tipi, üç boyutta; tüm şişe stilleri ve mektup kâğıtları ücretsiz","Denetim, bildirme ve engelleme ile huzurlu bir ortam"],
 "Bu bir arkadaşlık uygulaması ya da sosyal ağ değil; uyumadan önce küçük bir uğraş. Yalnızca 18+. Fiyatlar App Store'da gösterilir."),
"ar-SA": ("رسالة في زجاجة: بحر الليل", "سطور قليلة لليالي الفندق", "فندق,سفر,عمل,أرق,ليل,ملل,تسلية,رسالة,مجهول,هدوء,بحر,أمواج,يوميات",
 "في رحلة عمل وغرفة الفندق هادئة أكثر من اللازم؟\nاكتب بضعة أسطر، وضعها في زجاجة، واتركها لبحر الليلة. ثم التقط زجاجة شخص آخر واقرأ يومًا من حياة مسافر غريب.",
 ["بلا تسجيل: لا رقم هاتف ولا بريد إلكتروني، افتح واكتب","3 رميات و3 التقاطات مجانية يوميًا؛ الرد والدردشة وإرسال الصور مجانية دائمًا","رسوم متحركة متقنة: زجاجات تتمايل مع الموج، و«فرقعة» السدادة، وسماء تتبدّل مع الوقت","اختر خط اليد أو خط كاي أو الآلة الكاتبة بثلاثة أحجام؛ جميع أنماط الزجاجات والأوراق مجانية","المراجعة والإبلاغ والحظر تحافظ على الهدوء"],
 "ليس تطبيق تعارف ولا شبكة اجتماعية، بل تسلية صغيرة قبل النوم. لمن هم 18 عامًا فأكثر. الأسعار معروضة في App Store."),
}
PROMO = {"zh-Hans":"睡不着的出差夜，写几行字扔进海里。无需注册，每天免费扔 3 个、捡 3 个。","en-US":"A sleepless night on a work trip? Toss a few lines into the sea. No sign-up, 3 free throws and 3 free picks a day.",
"zh-Hant":"睡不著的出差夜，寫幾行字丟進海裡。免註冊，每天免費丟 3 個、撿 3 個。","ja":"眠れない出張の夜に、数行の手紙を海へ。登録不要、毎日 3 回流せて 3 回拾えます。",
"ko":"잠 못 드는 출장의 밤, 몇 줄 적어 바다에 띄워 보세요. 가입 없이 매일 3번 띄우고 3번 주울 수 있어요.","es-ES":"¿Una noche de viaje sin sueño? Lanza unas líneas al mar. Sin registro, 3 lanzamientos y 3 recogidas gratis al día.",
"fr-FR":"Une nuit blanche en déplacement ? Confiez quelques lignes à la mer. Sans inscription, 3 lancers et 3 repêchages gratuits par jour.",
"de-DE":"Schlaflos auf Dienstreise? Schick ein paar Zeilen aufs Meer. Ohne Anmeldung, täglich 3 Würfe und 3 Funde gratis.",
"pt-BR":"Sem sono numa viagem a trabalho? Jogue algumas linhas ao mar. Sem cadastro, 3 lançamentos e 3 pescas grátis por dia.",
"it":"Una notte insonne in trasferta? Affida due righe al mare. Senza registrazione, 3 lanci e 3 ripescaggi gratis al giorno.",
"ru":"Не спится в командировке? Отправьте пару строк в море. Без регистрации, 3 броска и 3 улова в день бесплатно.",
"th":"นอนไม่หลับในคืนที่ไปทำงานต่างเมือง? ส่งข้อความสักบรรทัดลงทะเล ไม่ต้องสมัคร โยนฟรี 3 เก็บฟรี 3 ทุกวัน",
"vi":"Mất ngủ trong chuyến công tác? Thả vài dòng xuống biển. Không cần đăng ký, mỗi ngày miễn phí 3 lần thả và 3 lần vớt.",
"id":"Tak bisa tidur saat dinas? Titipkan beberapa baris pada laut. Tanpa daftar, gratis 3 lempar dan 3 pungut setiap hari.",
"tr":"İş seyahatinde uykusuz bir gece mi? Denize birkaç satır bırak. Kayıt yok, her gün 3 atma ve 3 toplama ücretsiz.",
"ar-SA":"ليلة أرق في رحلة عمل؟ أرسل بضعة أسطر إلى البحر. بلا تسجيل، 3 رميات و3 التقاطات مجانية يوميًا."}
BANNED = ["交友","脱单","约会","dating","date ","citas","rencontre","namoro","incontri","знакомств","hẹn hò","kencan","arkadaşlık","تعارف","出会い","소개팅","交友","หาคู่","Dating"]
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "metadata")
for loc, (name, sub, kw, intro, bullets, outro) in M.items():
    assert len(name) <= 30 and len(sub) <= 30, (loc, len(name), len(sub))
    while len(kw) > 100: kw = kw.rsplit(",", 1)[0]  # App Store 关键词上限 100 字符：从末尾丢弃
    assert len(PROMO[loc]) <= 170
    desc = intro + "\n\n" + "\n".join("• " + b for b in bullets) + "\n\n" + outro + "\n"
    d = os.path.join(root, loc); os.makedirs(d, exist_ok=True)
    for f, v in [("name", name), ("subtitle", sub), ("keywords", kw), ("description", desc), ("promotional_text", PROMO[loc])]:
        open(os.path.join(d, f + ".txt"), "w", encoding="utf-8").write(v.rstrip("\n") + "\n")
    # 仅允许在“不是交友软件”的否定句中出现这些词
    for w in BANNED:
        for txt in (name, sub, kw, PROMO[loc], intro, "".join(bullets)):
            assert w not in txt, (loc, w)
print("wrote", len(M), "locales")
