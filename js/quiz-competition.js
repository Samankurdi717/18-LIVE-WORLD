/* KURD HALO — multilingual timed quiz */
(function(){
 'use strict';
 const home=document.getElementById('unifiedHub');
 const nav=document.getElementById('mainBottomNav');
 if(!home||!nav)return;
 const css=document.createElement('style');
 css.textContent=`
 #khQuizEntry{margin:12px 10px;padding:18px;border:1px solid #b18a43;border-radius:18px;background:linear-gradient(145deg,#18251e,#15151d);color:#f8edda}
 #khQuizEntry h2{color:#f0ce7d;margin:0 0 7px}
 .khq-page{position:fixed;inset:96px 0 62px;z-index:140;overflow:auto;background:#090a16;color:#fff;padding:14px 13px 30px}
 .khq-page.hidden{display:none!important}
 .khq-hero,.khq-panel{max-width:620px;margin:0 auto 13px;border:1px solid #78613b;border-radius:18px;padding:17px;background:linear-gradient(145deg,#202b23,#171820)}
 .khq-hero{text-align:center;padding:23px 15px}.khq-hero h1{color:#f0ce7d;margin:8px 0}
 .khq-muted{color:#c9c4b7;font-size:13px;line-height:1.7}
 .khq-btn{display:block;width:100%;margin:8px 0;padding:13px;border:1px solid #8a7042;border-radius:12px;background:#27271f;color:#fff;text-align:center;font-weight:800}
 .khq-btn.primary{background:#b18a43;color:#17130c}
 .khq-btn:disabled{opacity:.75}
 .khq-lang-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
 .khq-lang{padding:13px;border:1px solid #75613f;border-radius:12px;background:#24231d;color:#fff;font-weight:800}
 .khq-lang.selected{border:2px solid #f0ce7d;background:#3a301d}
 #khqAnswers .khq-btn{text-align:right}
 #khqTimer{font-size:28px;color:#f0ce7d;font-weight:900;text-align:center}
 #khqBar{height:8px;background:#333;border-radius:9px;overflow:hidden;margin:8px 0 14px}
 #khqBar span{display:block;height:100%;width:100%;background:#d3a84e;transition:width .2s linear}
 #khqFeedback{min-height:28px;color:#f0ce7d;font-weight:800}
 @media(min-width:701px){.khq-page{left:50%;right:auto;transform:translateX(-50%);width:min(100%,620px)}}
 `;
 document.head.appendChild(css);
 const entry=document.createElement('section');
 entry.id='khQuizEntry';
 entry.innerHTML='<h2>🧠 پێشبڕکێی پرسیار و وەڵام</h2><p class="khq-muted">چوار زمان • ١٢ چرکە • ١٠ خاڵ بۆ وەڵامی دروست</p><button class="khq-btn primary" type="button" onclick="switchAppTab(\'quiz\')">🚀 چوونە ناو پێشبڕکێ</button>';
 home.insertBefore(entry,home.firstChild);
 const page=document.createElement('section');
 page.id='khQuizPage';page.className='khq-page hidden';page.dir='auto';
 page.innerHTML=`
  <div class="khq-hero"><div>KURD HALO • 🌍</div><h1>پێشبڕکێی پرسیار و وەڵام</h1><p class="khq-muted">زمانەکەت هەڵبژێرە، پاشان یاری دەست پێبکە</p></div>
  <div class="khq-panel" id="khqSetup">
   <h3>🌐 زمانی نووسینی پرسیار</h3>
   <div class="khq-lang-grid">
    <button class="khq-lang selected" data-lang="ku">کوردی</button><button class="khq-lang" data-lang="fa">فارسی</button>
    <button class="khq-lang" data-lang="ar">العربية</button><button class="khq-lang" data-lang="en">English</button>
   </div>
   <p class="khq-muted">زمانی هەڵبژێردراو تەنها بۆ خۆتە؛ بەشداربووانی تر دەتوانن زمانی جیاواز هەڵبژێرن. هەموو پرسیار و وەڵامەکان تەنها بە نووسینن.</p>
   <button class="khq-btn primary" id="khqStart">▶ یاریی تاقیکردنەوە بە تەنیا</button><hr><h3>👥 پێشبڕکێی گرووپی</h3><input id="khqNickname" type="text" maxlength="40" placeholder="ناوی یاریزان"><button class="khq-btn" id="khqCreateRoom">➕ دروستکردنی ژووری پێشبڕکێ</button><input id="khqRoomCode" type="text" maxlength="6" placeholder="کۆدی ژوور"><button class="khq-btn" id="khqJoinRoom">🔑 چوونە ناو ژوور</button><div class="khq-muted" id="khqRoomStatus" aria-live="polite"></div><div id="khqLobby" class="hidden"><h3 id="khqRoomTitle"></h3><div id="khqPlayers" class="khq-muted"></div><button class="khq-btn primary hidden" id="khqHostStart">🚦 دەستپێکردنی پێشبڕکێ</button></div>
   <p class="khq-muted" id="khqVoiceNote" aria-live="polite">هیچ دەنگێک یان خوێندنەوەیەکی خۆکار نییە؛ هەموو شتێک تەنها بە نووسین پیشان دەدرێت.</p>
  </div>
  <div class="khq-panel hidden" id="khqGame">
   <div class="khq-muted" id="khqCategory"></div><div class="khq-muted" id="khqProgress"></div>
   <div id="khqTimer">١٢</div><div id="khqBar"><span></span></div>
   <h3 id="khqQuestion"></h3><div id="khqAnswers"></div>
   <div id="khqFeedback" aria-live="polite"></div>
   <div class="khq-muted" id="khqScore"></div>
   <button class="khq-btn primary hidden" id="khqNext">پرسیاری داهاتوو</button>
  </div>
  <div class="khq-panel hidden" id="khqResult"><h2>🏆 ئەنجامی یاری</h2><h1 id="khqFinalScore"></h1><p class="khq-muted">ئەم قۆناغە وەشانی سەرەتایی یارییە؛ ژووری پێشبڕکێی ڕاستەقینەی چەند بەشداربوو پاش بەستنەوەی Supabase زیاد دەکرێت.</p><button class="khq-btn primary" id="khqAgain">دووبارە یاری بکە</button></div>
  <button class="khq-btn" onclick="switchAppTab('home')">↩ گەڕانەوە بۆ سەرەکی</button>`;
 nav.parentNode.insertBefore(page,nav);
 const bank=[
 {cat:'ئاینی / دین / Religion',correct:0,ku:{q:'مانگی ڕۆژوو لە ئیسلامدا کامەیە؟',a:['ڕەمەزان','شەعبان','شەوال','محەڕەم']},fa:{q:'ماه روزه در اسلام کدام است؟',a:['رمضان','شعبان','شوال','محرم']},ar:{q:'ما شهر الصيام في الإسلام؟',a:['رمضان','شعبان','شوال','محرم']},en:{q:'Which month is observed for fasting in Islam?',a:['Ramadan','Sha’ban','Shawwal','Muharram']}},
 {cat:'مەسیحی / مسیحیت / Christianity',correct:1,ku:{q:'کتێبی پیرۆزی مەسیحییەکان بە گشتی بە چەند بەشی سەرەکی دابەش دەبێت؟',a:['یەک','دوو','سێ','چوار']},fa:{q:'کتاب مقدس مسیحیان به چند بخش اصلی تقسیم می‌شود؟',a:['یک','دو','سه','چهار']},ar:{q:'إلى كم قسمين رئيسيين يُقسَّم الكتاب المقدس المسيحي؟',a:['قسم واحد','قسمين','ثلاثة أقسام','أربعة أقسام']},en:{q:'Into how many main sections is the Christian Bible commonly divided?',a:['One','Two','Three','Four']}},
 {cat:'یەزیدی / ایزدی / Yazidi',correct:3,ku:{q:'لە کۆمەڵگای یەزیدیدا پەرستگای پیرۆزی لالش لە کوێیە؟',a:['دهۆک','هەولێر','شەنگال','نەینەوا']},fa:{q:'زیارتگاه مقدس لالش در جامعه ایزدی در کدام منطقه قرار دارد؟',a:['دهوک','اربیل','سنجار','نینوا']},ar:{q:'أين يقع معبد لالش المقدس لدى الإيزيديين؟',a:['دهوك','أربيل','سنجار','نينوى']},en:{q:'Where is the Yazidi holy sanctuary of Lalish located?',a:['Duhok','Erbil','Sinjar','Nineveh']}},
 {cat:'کلدانی / کلدانیان / Chaldean',correct:0,ku:{q:'کڵدانییە کاتۆلیکەکان بە شێوەی سەرەکی پەیوەستن بە کام کڵێسا؟',a:['کڵێسای کڵدانی کاتۆلیک','کڵێسای ئەرمەنی','کڵێسای قۆپتی','کڵێسای مارۆنی']},fa:{q:'کاتولیک‌های کلدانی عمدتاً به کدام کلیسا وابسته‌اند؟',a:['کلیسای کاتولیک کلدانی','کلیسای ارمنی','کلیسای قبطی','کلیسای مارونی']},ar:{q:'إلى أي كنيسة ينتمي الكلدان الكاثوليك أساساً؟',a:['الكنيسة الكلدانية الكاثوليكية','الكنيسة الأرمنية','الكنيسة القبطية','الكنيسة المارونية']},en:{q:'Which church are Chaldean Catholics primarily affiliated with?',a:['Chaldean Catholic Church','Armenian Church','Coptic Church','Maronite Church']}},
 {cat:'کوردستان / کردستان / Kurdistan',correct:1,ku:{q:'کام شار بە پایتەختی هەرێمی کوردستان ناسراوە؟',a:['سلێمانی','هەولێر','دهۆک','هەڵەبجە']},fa:{q:'کدام شهر مرکز اقلیم کردستان عراق است؟',a:['سلیمانیه','اربیل','دهوک','حلبچه']},ar:{q:'ما المدينة التي تُعد عاصمة إقليم كردستان العراق؟',a:['السليمانية','أربيل','دهوك','حلبجة']},en:{q:'Which city is the capital of the Kurdistan Region of Iraq?',a:['Sulaymaniyah','Erbil','Duhok','Halabja']}},
 {cat:'عێراق / عراق / Iraq',correct:2,ku:{q:'کام ڕووبار لە بەغدا تێدەپەڕێت؟',a:['فورات','کارون','دیجلە','ئوردون']},fa:{q:'کدام رود از بغداد می‌گذرد؟',a:['فرات','کارون','دجله','اردن']},ar:{q:'أي نهر يمر عبر بغداد؟',a:['الفرات','كارون','دجلة','الأردن']},en:{q:'Which river flows through Baghdad?',a:['Euphrates','Karun','Tigris','Jordan']}},
 {cat:'ئێران / ایران / Iran',correct:0,ku:{q:'پایتەختی ئێران کام شارە؟',a:['تاران','ئیسفەهان','شیراز','تەورێز']},fa:{q:'پایتخت ایران کدام شهر است؟',a:['تهران','اصفهان','شیراز','تبریز']},ar:{q:'ما عاصمة إيران؟',a:['طهران','أصفهان','شيراز','تبريز']},en:{q:'What is the capital of Iran?',a:['Tehran','Isfahan','Shiraz','Tabriz']}},
 {cat:'وڵاتە عەرەبییەکان / کشورهای عربی / Arab countries',correct:3,ku:{q:'کام زمانە لە زۆربەی وڵاتە عەرەبییەکان زمانی فەرمییە؟',a:['تورکی','فارسی','ئوردی','عەرەبی']},fa:{q:'کدام زبان در بیشتر کشورهای عربی زبان رسمی است؟',a:['ترکی','فارسی','اردو','عربی']},ar:{q:'ما اللغة الرسمية في معظم الدول العربية؟',a:['التركية','الفارسية','الأردية','العربية']},en:{q:'Which language is official in most Arab countries?',a:['Turkish','Persian','Urdu','Arabic']}},
 {cat:'ئەورووپا / اروپا / Europe',correct:1,ku:{q:'پایتەختی ئیسپانیا کامەیە؟',a:['بارسێلۆنا','مەدرید','ڤالێنسیا','سێڤییا']},fa:{q:'پایتخت اسپانیا کدام است؟',a:['بارسلونا','مادرید','والنسیا','سویا']},ar:{q:'ما عاصمة إسبانيا؟',a:['برشلونة','مدريد','فالنسيا','إشبيلية']},en:{q:'What is the capital of Spain?',a:['Barcelona','Madrid','Valencia','Seville']}},
 {cat:'ئاسیا / آسیا / Asia',correct:0,ku:{q:'بەرزترین چیای جیهان کامەیە؟',a:['ئێڤەرێست','K2','کلیمانجارۆ','ئەلبروس']},fa:{q:'بلندترین کوه جهان کدام است؟',a:['اورست','کی۲','کلیمانجارو','البروس']},ar:{q:'ما أعلى جبل في العالم؟',a:['إيفرست','كي 2','كليمنجارو','إلبروس']},en:{q:'What is the highest mountain in the world?',a:['Mount Everest','K2','Kilimanjaro','Elbrus']}},
 {cat:'قارەی ئەمریکا / قاره آمریکا / The Americas',correct:2,ku:{q:'ڕووباری ئەمازۆن بە زۆری لە کام وڵاتدا دەڕوات؟',a:['پێرو','کۆلۆمبیا','بەرازیل','چیلی']},fa:{q:'رود آمازون بیشتر در کدام کشور جریان دارد؟',a:['پرو','کلمبیا','برزیل','شیلی']},ar:{q:'في أي دولة يجري معظم نهر الأمازون؟',a:['بيرو','كولومبيا','البرازيل','تشيلي']},en:{q:'In which country does most of the Amazon River flow?',a:['Peru','Colombia','Brazil','Chile']}}
 ];
 const langs={ku:{voice:'ku-IQ',dir:'rtl'},fa:{voice:'fa-IR',dir:'rtl'},ar:{voice:'ar-SA',dir:'rtl'},en:{voice:'en-US',dir:'ltr'}};
 let lang='ku',deck=[],index=0,score=0,answered=false,timer=null,seconds=12,questionBank=bank;
 const $=id=>document.getElementById(id);
 function speak(text){ return; }
 document.querySelectorAll('.khq-lang').forEach(b=>b.addEventListener('click',()=>{lang=b.dataset.lang;document.querySelectorAll('.khq-lang').forEach(x=>x.classList.toggle('selected',x===b));page.dir=langs[lang].dir;}));
 function mix(a){return a.map(x=>({x,r:Math.random()})).sort((a,b)=>a.r-b.r).map(o=>o.x);}
 async function start(){
  clearInterval(timer);score=0;index=0;questionBank=bank;
  if(typeof db!=='undefined' && db && currentUser){
   try{
    const {data,error}=await db.from('kh_quiz_bank')
      .select('id,category,translations,correct_option')
      .eq('status','published');
    if(!error && Array.isArray(data) && data.length){
     questionBank=data.map(row=>({
      id:row.id,cat:row.category,correct:Number(row.correct_option),
      ku:row.translations.ku,fa:row.translations.fa,
      ar:row.translations.ar,en:row.translations.en
     })).filter(item=>['ku','fa','ar','en'].every(k=>
      item[k] && typeof item[k].q==='string' && Array.isArray(item[k].a) && item[k].a.length===4
     ));
     if(!questionBank.length)questionBank=bank;
    }
   }catch(e){console.warn('KURD HALO question bank fallback:',e);}
  }
  deck=mix(questionBank);
  $('khqSetup').classList.add('hidden');$('khqResult').classList.add('hidden');$('khqGame').classList.remove('hidden');render();
 }
 function render(){
  clearInterval(timer);answered=false;seconds=12;
  const item=deck[index],t=item[lang],opts=t.a.map((label,i)=>({label,correct:i===item.correct}));
  const shuffled=mix(opts);item._answer=shuffled.findIndex(o=>o.correct);
  $('khqCategory').textContent=item.cat;$('khqProgress').textContent=(index+1)+' / '+deck.length;
  $('khqQuestion').textContent=t.q;$('khqAnswers').innerHTML='';$('khqFeedback').textContent='';
  $('khqScore').textContent='⭐ '+score+' خاڵ';$('khqNext').classList.add('hidden');
  $('khqTimer').textContent='١٢';$('khqBar').firstElementChild.style.width='100%';
  shuffled.forEach((o,i)=>{const b=document.createElement('button');b.className='khq-btn';b.type='button';b.textContent=o.label;b.addEventListener('click',()=>answer(i));$('khqAnswers').appendChild(b);});
  speak(t.q+'. '+shuffled.map((o,i)=>String(i+1)+'. '+o.label).join('. '));
  timer=setInterval(()=>{seconds--; $('khqTimer').textContent=String(seconds);$('khqBar').firstElementChild.style.width=(seconds/12*100)+'%';if(seconds<=0)answer(-1);},1000);
 }
 function answer(i){
  if(answered)return;answered=true;clearInterval(timer);
  const item=deck[index],correct=i===item._answer;if(correct)score+=10;
  [...$('khqAnswers').children].forEach((b,n)=>{b.disabled=true;if(n===item._answer)b.style.borderColor='#70c58b';if(n===i&&!correct)b.style.borderColor='#d66b62';});
  const t=item[lang],right=$('khqAnswers').children[item._answer].textContent;
  const msg=lang==='fa'?(correct?'آفرین! پاسخ درست است.':'پاسخ درست: '+right):lang==='ar'?(correct?'أحسنت! إجابة صحيحة.':'الإجابة الصحيحة: '+right):lang==='en'?(correct?'Correct! Well done.':'Correct answer: '+right):(correct?'👏 وەڵامی ڕاستە!':'وەڵامی ڕاست: '+right);
  $('khqFeedback').textContent=msg;$('khqScore').textContent='⭐ '+score+' خاڵ';
  $('khqNext').classList.remove('hidden');$('khqNext').textContent=index===deck.length-1?'بینینی ئەنجام':'پرسیاری داهاتوو';
  speak(msg);
 }
 function next(){if(!answered)return;if(index<deck.length-1){index++;render();return;}clearInterval(timer);$('khqGame').classList.add('hidden');$('khqResult').classList.remove('hidden');$('khqFinalScore').textContent=score+' / '+(deck.length*10)+' خاڵ';}
 $('khqStart').addEventListener('click',start);$('khqNext').addEventListener('click',next);$('khqAgain').addEventListener('click',start);

 // Multiplayer room: every participant keeps their own display language.
 let groupRoomId=null,groupRoomCode='',groupHost=false,groupRoom=null,groupPlayers=[],groupChannel=null,groupTicker=null,groupAdvanceTimer=null,groupAnswered=false;
 function groupName(){try{return ($('khqNickname').value||currentUser?.user_metadata?.first_name||currentUser?.email?.split('@')[0]||'Player').trim().slice(0,40)||'Player';}catch(e){return 'Player';}}
 function roomStatus(msg){$('khqRoomStatus').textContent=msg;}
 async function enterRoom(id,code,host){
  groupRoomId=id;groupRoomCode=code;groupHost=host;
  $('khqLobby').classList.remove('hidden');$('khqRoomTitle').textContent='ژووری پێشبڕکێ: '+code;
  $('khqSetup').classList.add('hidden');$('khqGame').classList.add('hidden');$('khqResult').classList.add('hidden');
  await refreshGroupRoom();
  if(groupChannel)db.removeChannel(groupChannel);
  groupChannel=db.channel('khq-room-'+id)
   .on('postgres_changes',{event:'UPDATE',schema:'public',table:'kh_quiz_rooms',filter:'id=eq.'+id},payload=>{groupRoom=payload.new;onGroupRoomUpdate();})
   .on('postgres_changes',{event:'*',schema:'public',table:'kh_quiz_players',filter:'room_id=eq.'+id},()=>refreshGroupPlayers())
   .subscribe();
 }
 async function refreshGroupPlayers(){
  if(!groupRoomId)return;
  const {data,error}=await db.from('kh_quiz_players').select('user_id,nickname,language,score').eq('room_id',groupRoomId).order('score',{ascending:false});
  if(error){roomStatus('هەڵە لە خوێندنەوەی یاریزانان: '+error.message);return;}
  groupPlayers=data||[];
  $('khqPlayers').innerHTML=groupPlayers.map((p,i)=>'<div>'+(i+1)+'. '+escapeRoomText(p.nickname)+' — '+({ku:'کوردی',fa:'فارسی',ar:'عەرەبی',en:'English'}[p.language]||p.language)+' — ⭐ '+p.score+'</div>').join('');
  const me=groupPlayers.find(p=>p.user_id===currentUser?.id);
  if(me)$('khqScore').textContent='⭐ '+me.score+' خاڵ';
  $('khqHostStart').classList.toggle('hidden',!groupHost||!groupRoom||groupRoom.status!=='waiting');
  $('khqHostStart').disabled=groupPlayers.length<2;
 }
 function escapeRoomText(value){const d=document.createElement('div');d.textContent=value||'';return d.innerHTML;}
 async function refreshGroupRoom(){
  if(!groupRoomId)return;
  const {data,error}=await db.from('kh_quiz_rooms').select('*').eq('id',groupRoomId).single();
  if(error){roomStatus('هەڵە: '+error.message);return;}
  groupRoom=data;await refreshGroupPlayers();onGroupRoomUpdate();
 }
 async function createGroupRoom(){
  if(!currentUser){roomStatus('بۆ بەشداری، سەرەتا بچۆ ژوورەوە.');return;}
  roomStatus('ژووری پێشبڕکێ دروست دەکرێت...');
  const {data,error}=await db.rpc('kh_quiz_create_room',{p_language:lang,p_nickname:groupName()});
  if(error){roomStatus('هەڵە: '+error.message+' — پێویستە SQLی پێشبڕکێ لە Supabase جێبەجێ بکرێت.');return;}
  const row=Array.isArray(data)?data[0]:data;
  await enterRoom(row.room_id,row.room_code,true);roomStatus('ژوور دروست کرا. کۆدەکە بۆ هاوڕێکانت بنێرە.');
 }
 async function joinGroupRoom(){
  if(!currentUser){roomStatus('بۆ بەشداری، سەرەتا بچۆ ژوورەوە.');return;}
  const code=$('khqRoomCode').value.trim().toUpperCase();
  if(!code){roomStatus('کۆدی ژوور بنووسە.');return;}
  roomStatus('چوونە ناو ژوور...');
  const {data,error}=await db.rpc('kh_quiz_join_room',{p_code:code,p_language:lang,p_nickname:groupName()});
  if(error){roomStatus('نەتوانرا بچیتە ژوورەوە: '+error.message);return;}
  await enterRoom(data,code,false);roomStatus('بە سەرکەوتوویی چوویتە ناو ژوور.');
 }
 async function hostStartGroup(){
  if(!groupRoomId||!groupHost)return;
  const order=mix(bank.map((_,i)=>i));
  const {error}=await db.rpc('kh_quiz_start_room',{p_room_id:groupRoomId,p_question_order:order});
  if(error){roomStatus('نەتوانرا پێشبڕکێ دەست پێبکات: '+error.message);return;}
  await refreshGroupRoom();
 }
 function onGroupRoomUpdate(){
  if(!groupRoom)return;
  if(groupRoom.status==='active')renderGroupQuestion();
  if(groupRoom.status==='finished')showGroupResults();
  if(groupRoom.status==='waiting')refreshGroupPlayers();
 }
 function renderGroupQuestion(){
  if(!groupRoom||groupRoom.status!=='active')return;
  clearInterval(groupTicker);clearTimeout(groupAdvanceTimer);
  $('khqLobby').classList.add('hidden');$('khqSetup').classList.add('hidden');$('khqResult').classList.add('hidden');$('khqGame').classList.remove('hidden');
  const qid=groupRoom.question_order[groupRoom.question_index],item=bank[qid],t=item[lang];
  const shuffled=mix(t.a.map((label,original)=>({label,original})));
  groupAnswered=false;
  $('khqCategory').textContent=item.cat;$('khqProgress').textContent='پرسیاری '+(groupRoom.question_index+1)+' لە '+groupRoom.question_order.length+' • ژوور '+groupRoomCode;
  $('khqQuestion').textContent=t.q;$('khqAnswers').innerHTML='';$('khqFeedback').textContent='';$('khqNext').classList.add('hidden');
  shuffled.forEach(o=>{const b=document.createElement('button');b.className='khq-btn';b.textContent=o.label;b.addEventListener('click',()=>submitGroupAnswer(o.original,b));$('khqAnswers').appendChild(b);});
  speak(t.q+'. '+shuffled.map((o,i)=>(i+1)+'. '+o.label).join('. '));
  const started=Date.parse(groupRoom.question_started_at);
  function tick(){
   const left=Math.max(0,12-Math.floor((Date.now()-started)/1000));
   $('khqTimer').textContent=String(left);$('khqBar').firstElementChild.style.width=(left/12*100)+'%';
   if(left===0){
    clearInterval(groupTicker);
    [...$('khqAnswers').children].forEach(b=>{b.disabled=true;});
    const right=t.a[item.correct];$('khqFeedback').textContent=lang==='en'?'Correct answer: '+right:lang==='fa'?'پاسخ درست: '+right:lang==='ar'?'الإجابة الصحيحة: '+right:'وەڵامی ڕاست: '+right;
    speak($('khqFeedback').textContent);
    if(groupHost)groupAdvanceTimer=setTimeout(async()=>{const {error}=await db.rpc('kh_quiz_next_question',{p_room_id:groupRoomId});if(error)roomStatus(error.message);},1800);
   }
  }
  tick();groupTicker=setInterval(tick,250);
 }
 async function submitGroupAnswer(original,button){
  if(groupAnswered)return;groupAnswered=true;
  [...$('khqAnswers').children].forEach(b=>b.disabled=true);
  const {data,error}=await db.rpc('kh_quiz_submit_answer',{p_room_id:groupRoomId,p_question_index:groupRoom.question_index,p_selected_option:original});
  if(error){$('khqFeedback').textContent='وەڵام تۆمار نەکرا: '+error.message;return;}
  const row=Array.isArray(data)?data[0]:data;
  $('khqFeedback').textContent=lang==='en'?'Answer submitted':lang==='fa'?'پاسخ ثبت شد':lang==='ar'?'تم تسجيل الإجابة':'وەڵامەکەت تۆمار کرا';
  await refreshGroupPlayers();
 }
 async function showGroupResults(){
  clearInterval(groupTicker);clearTimeout(groupAdvanceTimer);
  await refreshGroupPlayers();$('khqGame').classList.add('hidden');$('khqLobby').classList.add('hidden');$('khqResult').classList.remove('hidden');
  $('khqFinalScore').textContent=groupPlayers.map((p,i)=>(i+1)+'. '+p.nickname+' — '+p.score+' ⭐').join(' | ');
  $('khqAgain').classList.add('hidden');
 }
 $('khqCreateRoom').addEventListener('click',createGroupRoom);
 $('khqJoinRoom').addEventListener('click',joinGroupRoom);
 $('khqHostStart').addEventListener('click',hostStartGroup);

 const oldSwitch=window.switchAppTab;
 window.switchAppTab=function(tab){
  page.classList.toggle('hidden',tab!=='quiz');
  if(tab==='quiz'){
   $('profilePage')?.classList.add('hidden');home.classList.add('hidden');
   $('inboxHub')?.classList.remove('active');$('soundHub')?.classList.add('hidden');
   document.querySelectorAll('#mainBottomNav button').forEach(b=>b.classList.remove('active'));
   page.scrollTop=0;return;
  }
  if(!page.classList.contains('hidden')){clearInterval(timer);if('speechSynthesis'in window)speechSynthesis.cancel();}
  return oldSwitch.apply(this,arguments);
 };
 window.addEventListener('pagehide',()=>{clearInterval(timer);if('speechSynthesis'in window)speechSynthesis.cancel();});
})();
