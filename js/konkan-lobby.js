/* KURD HALO — real Hawler KonKan matchmaking lobby
 * Requires supabase/konkan_multiplayer_rooms.sql to be run in Supabase.
 * This stage creates real authenticated 4-seat rooms; tile dealing is the next server-authoritative stage.
 */
(function () {
  'use strict';
  const page = document.getElementById('konkanPage');
  if (!page || !window.supabase || document.getElementById('khRealLobby')) return;

  const oldPreview = document.getElementById('konkanTablePreview');
  if (oldPreview) oldPreview.remove();

  const oldRoomPanel = Array.from(page.querySelectorAll('.konkan-panel')).find(panel => {
    const heading = panel.querySelector('h3');
    return heading && heading.textContent.includes('مێزی کۆنکان');
  });
  if (oldRoomPanel) oldRoomPanel.style.display = 'none';

  const style = document.createElement('style');
  style.textContent = `
    #khRealLobby{margin:14px 0;padding:16px;border:1px solid #b78b3d;border-radius:20px;color:#f8edda;background:radial-gradient(ellipse at top,#3b2b18,#17150f 62%,#10110f);box-shadow:0 12px 32px #0008}
    #khRealLobby h2{margin:0;color:#f3cc78;font-size:21px;text-align:center}
    #khRealLobby .kh-sub{font-size:12px;text-align:center;color:#d7c4a1;line-height:1.7}
    #khRealLobby .kh-actions{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin:14px 0}
    #khRealLobby button{width:100%;border:1px solid #c49a4b;border-radius:12px;padding:12px 8px;background:linear-gradient(145deg,#e5bd69,#a8752d);color:#1c150b;font-weight:900}
    #khRealLobby button.secondary{background:#26251e;color:#f5d995}
    #khRealLobby input{width:100%;box-sizing:border-box;border:1px solid #80663a;border-radius:11px;padding:12px;background:#100f0d;color:#fff;text-align:center;font-size:18px;letter-spacing:3px}
    #khRealLobby .kh-join{display:grid;grid-template-columns:1fr 110px;gap:8px}
    #khRealLobby .kh-board{display:grid;grid-template-columns:1fr 1fr 1fr;grid-template-rows:auto auto auto;gap:8px;margin:16px 0;align-items:center}
    #khRealLobby .kh-seat{min-height:64px;padding:9px 4px;border:1px solid #7e653b;border-radius:13px;background:#211c14;text-align:center;font-size:12px;display:flex;flex-direction:column;justify-content:center;gap:4px}
    #khRealLobby .kh-seat strong{font-size:13px;color:#f2d48c}
    #khRealLobby .kh-seat small{color:#bfb29a}
    #khRealLobby .kh-seat.a{border-color:#c49b43;background:linear-gradient(145deg,#3b2b13,#21190e)}
    #khRealLobby .kh-seat.b{border-color:#4d91c4;background:linear-gradient(145deg,#172b38,#151b20)}
    #khRealLobby .kh-seat.top{grid-column:2;grid-row:1}
    #khRealLobby .kh-seat.left{grid-column:1;grid-row:2}
    #khRealLobby .kh-center{grid-column:2;grid-row:2;text-align:center;padding:10px 2px;border:1px solid #c49b43;border-radius:14px;background:radial-gradient(ellipse,#5a3b1c,#24190f);font-size:12px}
    #khRealLobby .kh-seat.right{grid-column:3;grid-row:2}
    #khRealLobby .kh-seat.bottom{grid-column:2;grid-row:3}
    #khRealLobby .kh-status{margin:10px 0;padding:11px;border-radius:11px;background:#11130f;color:#e6d4b2;font-size:12px;line-height:1.8;text-align:center;min-height:42px}
    #khRealLobby .kh-code{font-size:25px;letter-spacing:5px;color:#f4d17d;text-align:center;margin:8px}
    #khRealLobby .kh-hidden{display:none!important}
    @media(max-width:360px){#khRealLobby .kh-actions{grid-template-columns:1fr}#khRealLobby .kh-seat{font-size:11px}}
  `;
  document.head.appendChild(style);

  const panel = document.createElement('section');
  panel.id = 'khRealLobby';
  panel.innerHTML = `
    <h2>🏛️ مێزی کۆنکانی هەولێر</h2>
    <p class="kh-sub">چوار یاریزانی ڕاستەقینە • دوو تیمی دوو کەسی • بێ بۆت</p>
    <div class="kh-actions">
      <button type="button" id="khQuickJoin">⚡ یاریی خێرا</button>
      <button type="button" class="secondary" id="khCreatePrivate">🔐 دروستکردنی ژووری تایبەت</button>
    </div>
    <div class="kh-join">
      <input id="khRoomCodeInput" maxlength="6" placeholder="کۆدی ژوور" aria-label="کۆدی ژوور">
      <button type="button" class="secondary" id="khJoinPrivate">چوونە ژوورەوە</button>
    </div>
    <div id="khRoomCodeDisplay" class="kh-code kh-hidden"></div>
    <div class="kh-board" aria-label="شوێنی چوار یاریزان">
      <div class="kh-seat a top" id="khSeat3"><strong>شوێنی ٣</strong><small>تیمی A • بەرامبەر تۆ</small></div>
      <div class="kh-seat b left" id="khSeat4"><strong>شوێنی ٤</strong><small>تیمی B</small></div>
      <div class="kh-center">🀄<br><strong>کۆنکانی هەولێر</strong><br><small id="khPlayerCount">٠ / ٤ یاریزان</small></div>
      <div class="kh-seat b right" id="khSeat2"><strong>شوێنی ٢</strong><small>تیمی B</small></div>
      <div class="kh-seat a bottom" id="khSeat1"><strong>شوێنی ١</strong><small>تۆ / سەرکردە</small></div>
    </div>
    <div id="khLobbyStatus" class="kh-status" aria-live="polite">یاریی خێرا هەڵبژێرە یان ژوورێکی تایبەت دروست بکە. بۆ چوونە یاری پێویستە بچیتە ژوورەوە.</div>
    <button type="button" class="kh-hidden" id="khStartRound">🀄 دەستپێکردن و دابەشکردنی کاشییەکان</button>
    <button type="button" class="secondary kh-hidden" id="khRefreshRoom">🔄 نوێکردنەوەی ژوور</button>
    <div id="khGameBoard" class="kh-hidden" style="margin-top:14px;padding:13px;border:1px solid #b78b3d;border-radius:16px;background:#17130e">
      <h3 style="margin:0 0 8px;color:#f3cc78;text-align:center">مێزی یاری • کاپ و دەستی تۆ</h3>
      <div id="khRoundInfo" class="kh-status"></div>
      <div id="khYourHand" style="display:flex;flex-wrap:wrap;gap:5px;justify-content:center"></div>
      <p class="kh-sub">کاشییەکانی دەستی تۆ تەنها بۆ خۆت دەردەکەون؛ دەستی یاریزانانی تر شاراوەیە.</p>
    </div>
  `;
  const daily = document.getElementById('konkanDailySpinPanel');
  if (daily && daily.parentNode === page) page.insertBefore(panel, daily);
  else page.insertBefore(panel, page.firstChild);

  const $ = id => document.getElementById(id);
  let activeRoomId = null;
  let activeRoomCode = null;
  let activeUserId = null;
  let activeHostId = null;
  let realtimeChannel = null;
  let busy = false;

  function status(message) { $('khLobbyStatus').textContent = message; }
  function setBusy(value) {
    busy = value;
    ['khQuickJoin','khCreatePrivate','khJoinPrivate'].forEach(id => { if ($(id)) $(id).disabled = value; });
  }
  function showError(error) {
    const msg = error && (error.message || error.details) ? (error.message || error.details) : 'هەڵەیەک ڕوویدا.';
    status('⚠️ ' + msg);
  }
  async function getUser() {
    const { data, error } = await db.auth.getSession();
    if (error) throw error;
    if (!data.session || !data.session.user) throw new Error('تکایە سەرەتا بچۆ ژوورەوە.');
    return data.session.user;
  }
  function paintSeats(players) {
    const bySeat = new Map((players || []).map(p => [Number(p.seat_no), p]));
    [1,2,3,4].forEach(n => {
      const el = $('khSeat' + n);
      const p = bySeat.get(n);
      if (!el) return;
      if (p) {
        const me = window.khKonkanUserId && p.user_id === window.khKonkanUserId;
        el.innerHTML = '<strong>' + (me ? 'تۆ' : 'یاریزانی ' + n) + '</strong><small>' +
          (n === 1 ? 'تیمی A • سەرکردە' : n === 3 ? 'تیمی A • بەرامبەر' : 'تیمی B') +
          '</small><span style="font-size:18px">👤</span>';
      } else {
        el.innerHTML = '<strong>شوێنی ' + n + '</strong><small>' + (n === 1 ? 'سەرکردە' : n === 4 ? 'هاوتیمی شوێنی ١' : 'چاوەڕێی یاریزان') + '</small><span style="font-size:18px;opacity:.45">＋</span>';
      }
    });
    $('khPlayerCount').textContent = (players || []).length + ' / ٤ یاریزان';
  }
  async function refreshRoom() {
    if (!activeRoomId) return;
    const { data: players, error } = await db.from('halo_konkan_room_players')
      .select('user_id,seat_no,team_no,joined_at').eq('room_id', activeRoomId).order('seat_no');
    if (error) throw error;
    paintSeats(players || []);
    const {data: roomMeta, error: roomError} = await db.from('halo_konkan_rooms').select('host_id,status').eq('id',activeRoomId).single();
    if (roomError) throw roomError;
    activeHostId = roomMeta.host_id;
    const full = (players || []).length === 4;
    $('khStartRound').classList.toggle('kh-hidden', !(full && activeHostId === activeUserId && roomMeta.status === 'waiting'));
    if (full) {
      status(activeHostId === activeUserId ? '✅ چوار یاریزان ئامادەن. تیمی A: شوێنی ١ و ٣؛ تیمی B: شوێنی ٢ و ٤. دوگمەی دەستپێکردن دابگرە.' : '✅ چوار یاریزان کۆبوونەتەوە. چاوەڕێی دەستپێکردنی سەرکردەی ژوورەکە بە.');
    } else {
      status('چاوەڕێی یاریزانانی تر... ' + (players || []).length + ' لە ٤ شوێن پڕە. هیچ بۆتێک زیاد ناکرێت.');
    }
  }
  async function loadRound() {
    if (!activeRoomId || !activeUserId) return;
    const {data: rounds,error: roundError}=await db.from('halo_konkan_rounds')
      .select('id,cap,joker_identity,captain_id,current_turn_id,draw_count,status,created_at')
      .eq('room_id',activeRoomId).order('created_at',{ascending:false}).limit(1);
    if(roundError) throw roundError;
    if(!rounds || !rounds.length) return;
    const round=rounds[0];
    const {data: handRow,error: handError}=await db.from('halo_konkan_round_hands')
      .select('tiles').eq('round_id',round.id).eq('user_id',activeUserId).single();
    if(handError) throw handError;
    const cap=round.cap;
    const joker=round.joker_identity;
    $('khRoundInfo').textContent='کاپ: '+cap.number+' / '+cap.color+' • ناسنامەی جوکەر: '+joker.number+' / '+joker.color+' • کاشیی ماوە: '+round.draw_count+' • '+(round.captain_id===activeUserId?'تۆ سەرکردەیت':'سەرکردەی ئەم دەورە یاریزانێکی ترە');
    $('khYourHand').innerHTML=(handRow.tiles||[]).map(tile=>{
      const label=tile.kind==='joker'?'🃏':tile.kind==='antique'?'🏛️':String(tile.number);
      const color=tile.kind==='number'?tile.color:tile.kind;
      return '<span style="min-width:31px;padding:9px 5px;border-radius:8px;background:linear-gradient(160deg,#fff7df,#d8c49b);border:1px solid #a88d5c;color:'+(color==='red'?'#c32626':color==='blue'?'#1767b3':color==='yellow'?'#987000':'#222')+';font-weight:900;text-align:center">'+label+'</span>';
    }).join('');
    $('khGameBoard').classList.remove('kh-hidden');
    $('khStartRound').classList.add('kh-hidden');
  }

  async function watchRoom(roomId) {
    activeRoomId = roomId;
    if (realtimeChannel) await db.removeChannel(realtimeChannel);
    realtimeChannel = db.channel('kh-konkan-room-' + roomId)
      .on('postgres_changes',{event:'*',schema:'public',table:'halo_konkan_room_players',filter:'room_id=eq.'+roomId},() => {
        refreshRoom().catch(showError);
      })
      .on('postgres_changes',{event:'INSERT',schema:'public',table:'halo_konkan_rounds',filter:'room_id=eq.'+roomId},() => {
        loadRound().catch(showError);
      })
      .on('postgres_changes',{event:'*',schema:'public',table:'halo_konkan_rooms',filter:'id=eq.'+roomId},() => {
        refreshRoom().catch(showError);
      }).subscribe();
    $('khRefreshRoom').classList.remove('kh-hidden');
    $('khRoomCodeDisplay').textContent = activeRoomCode || '';
    $('khRoomCodeDisplay').classList.toggle('kh-hidden', !activeRoomCode);
    await refreshRoom();
    await loadRound();
  }
  async function enterRoom(rpcName, args) {
    if (busy) return;
    setBusy(true);
    try {
      const user = await getUser();
      window.khKonkanUserId = user.id;
      activeUserId = user.id;
      const { data, error } = await db.rpc(rpcName, args || {});
      if (error) throw error;
      activeRoomId = data.room_id;
      activeRoomCode = data.room_code || null;
      await watchRoom(activeRoomId);
    } catch (error) {
      showError(error);
    } finally {
      setBusy(false);
    }
  }

  $('khQuickJoin').addEventListener('click', () => enterRoom('halo_konkan_quick_match'));
  $('khCreatePrivate').addEventListener('click', () => enterRoom('halo_konkan_create_private_room'));
  $('khJoinPrivate').addEventListener('click', () => {
    const code = $('khRoomCodeInput').value.trim().toUpperCase();
    if (code.length !== 6) { status('تکایە کۆدی ٦ پیت/ژمارەی ژوور بنووسە.'); return; }
    enterRoom('halo_konkan_join_private_room',{p_code:code});
  });
  $('khRefreshRoom').addEventListener('click', () => refreshRoom().catch(showError));
  $('khStartRound').addEventListener('click', async () => {
    if (!activeRoomId || busy) return;
    setBusy(true);
    try {
      const {data,error}=await db.rpc('halo_konkan_start_round',{p_room_id:activeRoomId});
      if(error) throw error;
      await loadRound();
      status('🎉 کاشییەکان بە سەرکەوتوویی لە سێرڤەری یاری دابەش کران.');
    } catch(error) { showError(error); }
    finally { setBusy(false); }
  });
  $('khRoomCodeInput').addEventListener('input', function () {
    this.value = this.value.replace(/[^a-z0-9]/gi,'').toUpperCase().slice(0,6);
  });

  db.auth.onAuthStateChange((_event, session) => {
    if (!session) {
      activeRoomId = null;
      activeRoomCode = null;
      if (realtimeChannel) db.removeChannel(realtimeChannel);
      realtimeChannel = null;
      paintSeats([]);
      status('بۆ چوونە ژوورەوەی یاری، تکایە بچۆ ژوورەوە بە ئەکاونتی KURD HALO.');
    }
  });
})();
