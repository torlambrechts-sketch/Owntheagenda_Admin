// Sentral admin — shared seed data (demo tenant: Lumio AS / Kari Nordmann). Deterministic: same seed every load.
(function () {
  let s = 11;
  const rnd = () => { s = (s * 16807) % 2147483647; return (s - 1) / 2147483646; };
  const pick = (a) => a[Math.floor(rnd() * a.length)];
  const int = (a, b) => a + Math.floor(rnd() * (b - a + 1));
  const nb = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, '\u00A0');
  const kr = (n) => nb(n) + ' kr';
  const pct = (n) => (Math.round(n * 10) / 10).toString().replace('.', ',') + ' %';
  const ICON = {
    dashboard: 'M4 4h7v7H4zM13 4h7v4h-7zM13 10h7v10h-7zM4 13h7v7H4z',
    building: 'M5 21V5a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v16M15 10h3a1 1 0 0 1 1 1v10M3 21h18M8 8h3M8 12h3M8 16h3',
    pulse: 'M3 12h4l2-5 4 10 2-5h6',
    users: 'M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20M10 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7M20 20v-1.5a3.5 3.5 0 0 0-2.5-3.35M15.5 4.2a3.5 3.5 0 0 1 0 6.6',
    ticket: 'M4 8a2 2 0 0 0 0 4v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4a2 2 0 0 1 0-4V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1zM14 4v13',
    target: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8M12 12h.01',
    kanban: 'M4 4h4v16H4zM10 4h4v10h-4zM16 4h4v6h-4z',
    inbox: 'M4 13l2.5-8h11L20 13v6H4zM4 13h5l1 2h4l1-2h5',
    mail: 'M4 6h16v12H4zM4 7l8 6 8-6',
    contacts: 'M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6zM12 12a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5M8.5 17a3.5 3.5 0 0 1 7 0M4 7h2M4 12h2M4 17h2',
    list: 'M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01',
    filter: 'M4 5h16l-6 7.5V19l-4 1v-7.5z',
    template: 'M5 4h14v16H5zM8 8h8M8 12h8M8 16h5',
    flag: 'M5 21V4M5 4h11l-2 4 2 4H5',
    chart: 'M4 20V4M4 20h16M8 16v-4M12 16V8M16 16v-6',
    coins: 'M9 11a5 3 0 1 0 0-.01M4 11v4c0 1.66 2.24 3 5 3s5-1.34 5-3v-4M14 7.3c.6-.2 1.3-.3 2-.3 2.76 0 5 1.34 5 3v4c0 1.4-1.6 2.6-3.8 2.9',
    search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14M20 20l-4-4',
    puzzle: 'M9 4h4v2a1.5 1.5 0 0 0 3 0V4h4v4h-2a1.5 1.5 0 0 0 0 3h2v4h-4v-2a1.5 1.5 0 0 0-3 0v2H9v-4H7a1.5 1.5 0 0 1 0-3h2zM9 15v5h11v-5',
    globe: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3',
    activity: 'M4 12h3l3 7 4-14 3 7h3',
    log: 'M8 4h8l3 3v13H5V4zM9 10h6M9 14h6M9 18h3',
    shield: 'M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6zM9 12l2 2 4-4',
    page: 'M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h6',
    redirect: 'M4 17V9a3 3 0 0 1 3-3h11M15 3l3 3-3 3M20 21H10',
    close: 'M6 6l12 12M18 6L6 18',
    calendar: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
    phone: 'M7 3h10v18H7zM11 18h2',
    mic: 'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3M5 11a7 7 0 0 0 14 0M12 18v3',
    bolt: 'M13 3L5 14h6l-1 7 8-11h-6z',
    sliders: 'M4 7h10M18 7h2M4 17h4M12 17h8M16 5v4M10 15v4',
    bell: 'M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20a2 2 0 0 0 4 0',
    chevron: 'M6 9l6 6 6-6',
    plus: 'M12 5v14M5 12h14',
  };
  const products = [
    { id: 'orgpuls', name: 'Orgpuls', desc: 'Work-environment surveys', color: '#DCEBD3', ink: '#20431C', api: 'api.orgpuls.com/v2', version: 'v2.14.0', status: 'Operational', latency: 182, err: 0.2, rpm: 1240, lastSync: '40 s ago', region: 'EU · Stockholm', keys: 3, hooks: 6, since: 'Mar 2024' },
    { id: 'skiftly', name: 'Skiftly', desc: 'Shift planning', color: '#CFE0F5', ink: '#1F3A5C', api: 'api.skiftly.no/v1', version: 'v1.9.3', status: 'Degraded', latency: 640, err: 2.4, rpm: 610, lastSync: '3 min ago', region: 'EU · Frankfurt', keys: 2, hooks: 4, since: 'Jan 2025' },
    { id: 'avvik', name: 'Avvikspunkt', desc: 'HSE incident reporting', color: '#F6D9C6', ink: '#6B240C', api: 'api.avvikspunkt.no/v1', version: 'v1.3.1', status: 'Operational', latency: 210, err: 0.4, rpm: 290, lastSync: '1 min ago', region: 'EU · Stockholm', keys: 2, hooks: 3, since: 'Aug 2025' },
    { id: 'kurs', name: 'Kursrom', desc: 'Mandatory training', color: '#E7DAF2', ink: '#3E2A5C', api: 'api.kursrom.no/v1', version: 'v0.8.0', status: 'Beta', latency: 260, err: 0.9, rpm: 85, lastSync: '6 min ago', region: 'EU · Stockholm', keys: 1, hooks: 1, since: 'Jun 2026' },
  ];
  const staff = [
    { id: 'tor', name: 'Tor Lambrechts', ini: 'TL', role: 'Super-admin', team: 'Leadership', email: 'tor@orgpuls.no', mfa: 'App', last: 'Now' },
    { id: 'ingrid', name: 'Ingrid Solberg', ini: 'IS', role: 'Sales', team: 'Sales', email: 'ingrid@orgpuls.no', mfa: 'App', last: '12 min ago' },
    { id: 'eirik', name: 'Eirik Moen', ini: 'EM', role: 'Sales', team: 'Sales', email: 'eirik@orgpuls.no', mfa: 'App', last: '1 h ago' },
    { id: 'magnus', name: 'Magnus Berg', ini: 'MB', role: 'Support', team: 'Support', email: 'magnus@orgpuls.no', mfa: 'App', last: '4 min ago' },
    { id: 'hanna', name: 'Hanna Vik', ini: 'HV', role: 'Support', team: 'Support', email: 'hanna@orgpuls.no', mfa: 'Email code', last: '25 min ago' },
    { id: 'sara', name: 'Sara Haugen', ini: 'SH', role: 'Finance', team: 'Finance', email: 'sara@orgpuls.no', mfa: 'App', last: 'Yesterday' },
    { id: 'jonas', name: 'Jonas Dahl', ini: 'JD', role: 'Marketing', team: 'Growth', email: 'jonas@orgpuls.no', mfa: 'App', last: '2 h ago' },
    { id: 'emma', name: 'Emma Lie', ini: 'EL', role: 'Project', team: 'Delivery', email: 'emma@orgpuls.no', mfa: 'App', last: '3 h ago' },
    { id: 'ola', name: 'Ola Nilsen', ini: 'ON', role: 'Read-only analyst', team: 'Finance', email: 'ola@orgpuls.no', mfa: 'App', last: '2 days ago' },
  ];
  const staffById = Object.fromEntries(staff.map((x) => [x.id, x]));
  const bands = [
    { id: 'b1', label: '1–25', min: 1, max: 25, price: 265 },
    { id: 'b2', label: '26–100', min: 26, max: 100, price: 565 },
    { id: 'b3', label: '101–250', min: 101, max: 250, price: 1190 },
    { id: 'b4', label: '251–500', min: 251, max: 500, price: 2290 },
  ];
  const industries = ['Construction', 'Health and care', 'Education', 'Hospitality', 'Professional services', 'Public administration', 'Retail', 'Transport', 'Manufacturing', 'ICT', 'Aquaculture'];
  const fylker = ['Oslo', 'Akershus', 'Vestland', 'Rogaland', 'Trøndelag', 'Innlandet', 'Agder', 'Nordland', 'Møre og Romsdal', 'Troms', 'Vestfold', 'Buskerud', 'Østfold'];
  const cities = { Oslo: 'Oslo', Akershus: 'Lillestrøm', Vestland: 'Bergen', Rogaland: 'Stavanger', Trøndelag: 'Trondheim', Innlandet: 'Hamar', Agder: 'Kristiansand', Nordland: 'Bodø', 'Møre og Romsdal': 'Ålesund', Troms: 'Tromsø', Vestfold: 'Tønsberg', Buskerud: 'Drammen', Østfold: 'Fredrikstad' };
  const sources = ['Organic search', 'Paid search', 'Referral', 'Partner', 'Newsletter', 'Event', 'Direct', 'LinkedIn'];
  const orgNames = ['Lumio AS', 'Nordvik Anlegg AS', 'Bergheim Bygg AS', 'Solstrand Helse AS', 'Kvamme Regnskap AS', 'Tindra Barnehager AS', 'Havbris Sjømat AS', 'Elvebakken kommune', 'Nordlys Logistikk AS', 'Granli Eiendom AS', 'Brattli Tannklinikk', 'Mørkved IT AS', 'Strandby Hotell AS', 'Lyngvær Rør AS', 'Fjellheim skole', 'Askeland Advokat DA', 'Kystlinje Transport AS', 'Rimfrost Bakeri AS', 'Vardø Havn KF', 'Østmark Maskin AS', 'Tveit Omsorg AS', 'Sandvik Elektro AS', 'Lundegaard Arkitekter', 'Hovland Gartneri AS', 'Furuly Sykehjem', 'Blåfjell Reiseliv AS', 'Kråkerøy Marina AS', 'Nesodden Tannhelse', 'Skarpeid Revisjon AS', 'Torget Apotek AS', 'Engen Snekkeri AS', 'Polarlys Media AS', 'Heggedal Vekst AS', 'Røros Kobber AS', 'Lindeberg Klinikk AS', 'Mjøsa Energi AS', 'Fossheim Utleie AS', 'Valdres Fjellstue AS', 'Oddernes Bil AS', 'Grønli Barnehage SA', 'Stavsjø Laks AS', 'Bjørkly Pleie AS', 'Kirkenes Bygg AS', 'Sjøgata Kafé AS', 'Hamnvik Fiskeri AS', 'Bergtun Data AS'];
  const statuses = ['Active', 'Active', 'Active', 'Active', 'Active', 'Active', 'Trial', 'Trial', 'Trial', 'Past due', 'Cancelled', 'Suspended'];
  const orgs = orgNames.map((name, i) => {
    const fylke = i === 0 ? 'Oslo' : pick(fylker);
    const status = i === 0 ? 'Active' : i < 4 ? 'Trial' : pick(statuses);
    const band = i === 0 ? bands[1] : pick([bands[0], bands[0], bands[1], bands[1], bands[1], bands[2], bands[3]]);
    const employees = i === 0 ? 48 : int(band.min, band.max);
    const prods = ['orgpuls'];
    if (rnd() < 0.42) prods.push('skiftly');
    if (rnd() < 0.3) prods.push('avvik');
    if (rnd() < 0.12) prods.push('kurs');
    const mrr = status === 'Trial' || status === 'Cancelled' ? 0 : prods.reduce((a, p) => a + (p === 'orgpuls' ? band.price : p === 'skiftly' ? Math.round(band.price * 0.8) : p === 'avvik' ? Math.round(band.price * 0.6) : 190), 0);
    const health = i === 0 ? 82 : status === 'Past due' ? int(22, 45) : status === 'Suspended' ? int(10, 25) : status === 'Cancelled' ? int(5, 20) : int(34, 96);
    const signupDaysAgo = status === 'Trial' ? int(2, 29) : int(40, 900);
    return {
      id: 'o' + (i + 1), name, orgnr: (int(910, 999)) + '\u00A0' + nb(int(100, 999)) + '\u00A0' + nb(int(100, 999)),
      status, band: band.label, price: band.price, employees, industry: i === 0 ? 'Professional services' : pick(industries), fylke, city: cities[fylke],
      source: pick(sources), products: prods, mrr, health, owner: pick(['ingrid', 'eirik', 'tor']), csm: pick(['magnus', 'hanna']),
      trialLeft: status === 'Trial' ? 30 - signupDaysAgo : null, signupDaysAgo,
      lastSurvey: status === 'Trial' && rnd() < 0.5 ? null : int(1, 120), response: int(54, 93),
      labels: i === 0 ? ['Demo tenant', 'Pilot'] : rnd() < 0.3 ? [pick(['Champion', 'Renewal Q4', 'Municipality', 'Partner', 'Expansion'])] : [],
      parent: null, ehf: rnd() < 0.3,
    };
  });
  orgs[7].labels = ['Municipality']; orgs[7].ehf = true;
  orgs[2].parent = 'o7';
  const orgById = Object.fromEntries(orgs.map((o) => [o.id, o]));
  const first = ['Kari', 'Ole', 'Ingrid', 'Lars', 'Silje', 'Anders', 'Marte', 'Jon', 'Hilde', 'Per', 'Ida', 'Knut', 'Nora', 'Erik', 'Tone', 'Stian', 'Linn', 'Geir', 'Ane', 'Bjørn', 'Maria', 'Henrik', 'Camilla', 'Trond', 'Sofie', 'Håkon', 'Eva', 'Rune', 'Thea', 'Arne', 'Julie', 'Morten'];
  const last = ['Nordmann', 'Hansen', 'Johansen', 'Olsen', 'Larsen', 'Andersen', 'Pedersen', 'Nilsen', 'Kristiansen', 'Jensen', 'Karlsen', 'Berg', 'Haugen', 'Hagen', 'Eriksen', 'Bakken', 'Lie', 'Moen', 'Dahl', 'Lunde', 'Strand', 'Solheim', 'Aas', 'Brekke'];
  const roles = ['Daglig leder', 'HR', 'Leder', 'Verneombud'];
  const ctypes = ['Prospect', 'Trial user', 'Customer user', 'Customer user', 'Former customer'];
  const consents = ['Subscribed', 'Subscribed', 'Subscribed', 'No consent', 'Pending double opt-in', 'Unsubscribed', 'Bounced'];
  const people = first.map((f, i) => {
    const o = i === 0 ? orgs[0] : orgs[(i * 7) % orgs.length];
    const l = i === 0 ? 'Nordmann' : pick(last);
    const dom = o.name.toLowerCase().replace(/ (as|da|sa|kf)$/, '').replace(/[^a-zæøå]+/g, '').replace(/æ/g, 'ae').replace(/ø/g, 'o').replace(/å/g, 'a').slice(0, 14) + '.no';
    return {
      id: 'p' + (i + 1), name: f + ' ' + l, ini: f[0] + l[0], email: (f + '.' + l).toLowerCase().replace(/ø/g, 'o').replace(/å/g, 'a').replace(/æ/g, 'ae') + '@' + dom,
      phone: '+47 ' + int(400, 999) + ' ' + int(10, 99) + ' ' + int(100, 999), org: o.id, role: i === 0 ? 'Daglig leder' : pick(roles),
      type: i === 0 ? 'Customer user' : o.status === 'Trial' ? 'Trial user' : o.status === 'Cancelled' ? 'Former customer' : pick(ctypes),
      consent: i === 0 ? 'Subscribed' : pick(consents), consentDate: int(1, 28) + '.' + int(1, 9) + '.2026', source: pick(['Signup', 'Contact form', 'Newsletter', 'Event', 'Import', 'Prospect search', 'Web visitor']),
      owner: o.owner, labels: rnd() < 0.3 ? [pick(['Decision maker', 'Champion', 'Billing contact', 'Newsletter'])] : [], city: o.city, fylke: o.fylke, lastTouch: int(0, 60),
    };
  });
  const personById = Object.fromEntries(people.map((p) => [p.id, p]));
  const pipelines = [
    { id: 'new', name: 'New business', stages: [{ id: 's1', name: 'Qualified', prob: 10, rot: 14 }, { id: 's2', name: 'Discovery call', prob: 25, rot: 10 }, { id: 's3', name: 'Demo', prob: 40, rot: 10 }, { id: 's4', name: 'Proposal sent', prob: 60, rot: 7 }, { id: 's5', name: 'Negotiation', prob: 80, rot: 7 }] },
    { id: 'exp', name: 'Expansion and cross-sell', stages: [{ id: 'e1', name: 'Signal', prob: 15, rot: 21 }, { id: 'e2', name: 'Conversation', prob: 35, rot: 14 }, { id: 'e3', name: 'Offer', prob: 65, rot: 10 }, { id: 'e4', name: 'Agreement', prob: 85, rot: 7 }] },
    { id: 'pub', name: 'Public sector tenders', stages: [{ id: 't1', name: 'Notice found', prob: 5, rot: 30 }, { id: 't2', name: 'Bid preparation', prob: 30, rot: 14 }, { id: 't3', name: 'Submitted', prob: 50, rot: 45 }, { id: 't4', name: 'Award', prob: 90, rot: 14 }] },
  ];
  const labelDefs = [{ n: 'Hot', bg: '#F0B9A0', c: '#6B240C' }, { n: 'Warm', bg: '#F5DC96', c: '#5C4600' }, { n: 'Cold', bg: '#CFE0F5', c: '#1F3A5C' }, { n: 'Multi-product', bg: '#E7DAF2', c: '#3E2A5C' }, { n: 'Municipality', bg: '#DCEBD3', c: '#20431C' }, { n: 'Partner', bg: '#F3E2C9', c: '#5C4600' }];
  const dealTitles = ['Annual pulse + baseline', 'HR suite for 3 sites', 'Skiftly add-on', 'Avvikspunkt rollout', 'Kursrom pilot', 'Upgrade to 101–250 band', 'Group agreement', 'Verneombud training bundle', 'Renewal and expansion', 'Tender: HMS-system', 'Full platform', 'Survey for new department'];
  const deals = [];
  for (let i = 0; i < 34; i++) {
    const pl = i < 22 ? pipelines[0] : i < 29 ? pipelines[1] : pipelines[2];
    const st = pl.stages[i % pl.stages.length];
    const o = orgs[(i * 5 + 1) % orgs.length];
    const p = people.find((x) => x.org === o.id) || people[(i * 3) % people.length];
    const idle = rnd() < 0.22 ? int(15, 32) : int(0, 6);
    deals.push({
      id: 'd' + (101 + i), title: o.name.replace(/ (AS|DA|SA|KF)$/, '') + ' — ' + pick(dealTitles), org: o.id, person: p.id, value: int(8, 160) * 1000, currency: 'NOK', pipeline: pl.id, stage: st.id,
      owner: pick(['ingrid', 'eirik', 'ingrid', 'tor']), labels: rnd() < 0.55 ? [pick(labelDefs).n] : [], act: idle > st.rot ? 'overdue' : rnd() < 0.2 ? 'none' : 'planned', idle,
      score: int(18, 94), close: int(1, 28) + ' ' + pick(['Oct', 'Nov', 'Dec']), closeMonth: pick(['Oct', 'Nov', 'Dec', 'Jan']), source: pick(['Web form', 'Chatbot', 'Prospect search', 'Manual', 'Campaign', 'Web visitors', 'Import', 'API']),
      product: pick(['orgpuls', 'orgpuls', 'skiftly', 'avvik', 'kurs']), status: 'open', created: int(3, 120), followers: rnd() < 0.4 ? ['tor'] : [], participants: rnd() < 0.5 ? 2 : 0, days: [int(1, 9), int(1, 12), int(0, 8)],
    });
  }
  deals.push({ ...deals[0], id: 'd201', title: 'Fjellheim skole — Full platform', org: 'o15', stage: 's5', status: 'won', value: 84000, idle: 0 });
  deals.push({ ...deals[1], id: 'd202', title: 'Strandby Hotell — Skiftly add-on', org: 'o13', stage: 's4', status: 'lost', lostReason: 'Price', value: 36000, idle: 0 });
  deals[0].title = 'Lumio AS — Expansion to Skiftly'; deals[0].org = 'o1'; deals[0].person = 'p1'; deals[0].stage = 's4'; deals[0].value = 64000; deals[0].labels = ['Hot', 'Multi-product']; deals[0].act = 'planned'; deals[0].score = 86; deals[0].idle = 2;
  const today = { label: 'Monday 5 October 2026', short: 'Mon 5 Oct' };
  const actTypes = [{ id: 'call', n: 'Call', g: '☎' }, { id: 'meeting', n: 'Meeting', g: '◷' }, { id: 'task', n: 'Task', g: '✓' }, { id: 'deadline', n: 'Deadline', g: '⚑' }, { id: 'email', n: 'Email', g: '✉' }, { id: 'lunch', n: 'Lunch', g: '◒' }, { id: 'demo', n: 'Product demo', g: '▶' }];
  const actSubjects = { call: ['Follow-up call', 'Discovery call', 'Check-in on trial', 'Renewal call'], meeting: ['Demo with HR', 'Onboarding session', 'Quarterly review', 'Steering group'], task: ['Send proposal', 'Prepare quote', 'Update contact data', 'Check band reconciliation'], deadline: ['Tender deadline', 'Proposal expires', 'Contract renewal'], email: ['Send case study', 'Reply on pricing', 'Intro email'], lunch: ['Lunch with partner'], demo: ['Demo: Skiftly', 'Demo: Avvikspunkt'] };
  const activities = [];
  for (let i = 0; i < 30; i++) {
    const t = pick(actTypes); const d = deals[(i * 3) % 34];
    const day = int(-3, 6);
    activities.push({ id: 'a' + (i + 1), type: t.id, subject: pick(actSubjects[t.id]), day, hour: int(8, 16), min: pick([0, 0, 30]), dur: pick([15, 30, 30, 45, 60, 90]), owner: d.owner, deal: d.id, org: d.org, person: d.person, prio: pick(['High', 'Medium', 'Medium', 'Low']), done: day < 0 ? rnd() < 0.7 : false, guests: rnd() < 0.3 ? int(1, 4) : 0, video: t.id === 'meeting' || t.id === 'demo' });
  }
  const tktSubjects = [
    ['Incident', 'Survey delivery', 'Survey invitations not delivered to 14 employees'], ['Question', 'Getting started', 'How do we add verneombud to the results?'], ['Service request', 'Billing', 'Extend trial by 14 days — board meeting moved'],
    ['Incident', 'Survey delivery', 'Reminder sent twice to the whole company'], ['Question', 'Results and anonymity', 'Why is the warehouse team shown as «—»?'], ['Service request', 'Billing', 'Switch from card to EHF invoice'],
    ['Problem', 'Survey delivery', 'Mail provider rejecting @kommune.no domains'], ['Question', 'Sales', 'Price for 3 sites with 140 employees in total'], ['Service request', 'Personvern request', 'Deletion request from former employee'],
    ['Incident', 'Bug', 'Tiltak export to PDF shows empty pages'], ['Question', 'Tiltak', 'Can tiltak have two owners?'], ['Service request', 'Billing', 'Change plan to 26–100 band'],
    ['Question', 'Feature request', 'Nynorsk version of the survey'], ['Incident', 'Bug', 'Skiftly: shift swap not syncing to calendar'], ['Service request', 'Getting started', 'Data export for annual HSE report'],
    ['Question', 'Results and anonymity', 'Can HR see who answered?'], ['Incident', 'Survey delivery', 'SMS invitations delayed for night shift'], ['Question', 'Billing', 'Invoice reference missing PO number'],
    ['Service request', 'Personvern request', 'Access request under GDPR art. 15'], ['Problem', 'Bug', 'PDF renderer times out on large reports'], ['Question', 'Getting started', 'Import employees from Visma'],
    ['Incident', 'Billing', 'Payment failed but card is valid'], ['Question', 'Sales', 'Do you support SSO with Entra ID?'], ['Service request', 'Getting started', 'Transfer ownership to new daglig leder'],
  ];
  const queueFor = (cat) => (cat === 'Billing' ? 'Billing' : cat === 'Sales' ? 'Sales' : cat === 'Personvern request' ? 'Personvern' : 'Support');
  const tickets = tktSubjects.map(([type, cat, subject], i) => {
    const o = orgs[(i * 3 + (i === 0 ? 0 : 2)) % orgs.length]; const p = people.find((x) => x.org === o.id) || people[i % people.length];
    const impact = type === 'Problem' ? 'Many orgs' : pick(['One user', 'One org', 'One org', 'Many orgs']);
    const urgency = cat === 'Survey delivery' || type === 'Incident' ? (rnd() < 0.6 ? 'Blocking' : 'Not blocking') : 'Not blocking';
    const prio = impact === 'Many orgs' && urgency === 'Blocking' ? 'Urgent' : (impact === 'Many orgs' || urgency === 'Blocking') ? 'High' : impact === 'One org' ? 'Normal' : 'Low';
    const status = i < 3 ? 'New' : pick(['Open', 'Open', 'Waiting on customer', 'Waiting on us', 'Resolved', 'Closed']);
    const ageH = int(1, 140);
    const frtTarget = { Urgent: 4, High: 9, Normal: 18, Low: 45 }[prio];
    return { id: 'T-' + (2310 + i), type, cat, subject, org: o.id, person: p.id, queue: queueFor(cat), prio, impact, urgency, status, assignee: status === 'New' ? null : pick(['magnus', 'hanna', 'magnus', 'sara', 'ingrid']), ageH, frtTarget, responded: status !== 'New' && rnd() < 0.85, channel: pick(['In-app help', 'Email', 'Contact form', 'In-app help']), product: cat === 'Bug' && i === 13 ? 'skiftly' : pick(['orgpuls', 'orgpuls', 'orgpuls', 'skiftly', 'avvik']), csat: status === 'Closed' ? pick([5, 5, 4, 5, 3]) : null, problem: (i === 0 || i === 16 || i === 3) ? 'T-2316' : null, page: pick(['/malinger/ny', '/resultater', '/oppsett/ansatte', '/tiltak', '/innsikt']), browser: pick(['Chrome 129 · macOS', 'Edge 128 · Windows 11', 'Safari 18 · iOS']) };
  });
  const settings = [
    { key: 'contact_rule', n: 'Contact rule', opts: ['No rule', 'Source and basis required', 'Opt-in only'], def: 'No rule', applies: 'CRM-01, CRM-04, LGN-04, PRO-05, PRO-07, WEB-04, AIA-07, MTG-05, MOB-01', group: 'Contacts and consent' },
    { key: 'import_consent', n: 'Consent source on import', opts: ['Off', 'Required per row'], def: 'Off', applies: 'CRM-09', group: 'Contacts and consent' },
    { key: 'sales_consent', n: 'Consent and suppression checks on sales email', opts: ['Off', 'Warn', 'Block'], def: 'Off', applies: 'COM-07, AUT-07, AUT-12', group: 'Contacts and consent' },
    { key: 'tracking', n: 'Email open and click tracking', opts: ['On', 'Off', 'Chosen per email'], def: 'On', applies: 'COM-06', group: 'Tracking' },
    { key: 'form_tracking', n: 'Form tracking fields (UTM, cookies, referrer)', opts: ['On', 'Off'], def: 'On', applies: 'LGN-03', group: 'Tracking' },
    { key: 'web_ident', n: 'Web visitor identification', opts: ['On', 'Off'], def: 'On', applies: 'WEB-01 to WEB-04', group: 'Tracking' },
    { key: 'widget_consent', n: 'Consent-gated loading of site widgets', opts: ['Off', 'On'], def: 'Off', applies: 'LGN-05', group: 'Tracking' },
    { key: 'second_admin', n: 'Second-admin approval for bulk deletes and merges', opts: ['Off', 'On'], def: 'Off', applies: 'PIP-10, CRM-11, CRM-12', group: 'Approvals and audit' },
    { key: 'typed_reason', n: 'Typed reason for CRM actions', opts: ['Off', 'On'], def: 'Off', applies: 'Every CRM write and read of customer data', group: 'Approvals and audit' },
    { key: 'count_limits', n: 'Count limits (workflow actions and delays, group-email recipients, webhooks per user, signers, options per field, score models)', opts: ['Unlimited', 'A number'], def: 'Unlimited', applies: 'AUT-05, AUT-07, COM-07, INT-04, DOC-05, CUS-01, PRO-03', group: 'Limits' },
    { key: 'plan_gates', n: 'Plan gates and usage limits', opts: ['All on and unlimited', 'Set per plan'], def: 'All on and unlimited', applies: 'ENT-01, ENT-02', group: 'Limits' },
    { key: 'api_rate', n: 'API rate limits', opts: ['Off', 'Source values', 'Custom'], def: 'Off', applies: 'INT-03', group: 'Limits' },
    { key: 'safeguards', n: 'Technical safeguards: workflow loop protection, webhook retry and ban policy', opts: ['Source values', 'Custom', 'Off'], def: 'Source values', applies: 'AUT-09, INT-04', group: 'Technical safeguards' },
    { key: 'rec_notice', n: 'Recording consent notices to attendees', opts: ['On with 24 hours’ notice', 'Custom timing', 'Off'], def: 'On with 24 hours’ notice', applies: 'MTG-02, MTG-08', group: 'Meetings' },
    { key: 'firewall', n: 'Anonymity firewall', opts: ['Fixed'], def: 'Fixed', applies: 'Every feature — a platform constant', group: 'Platform constant', fixed: true },
  ];
  const months = ['Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'];
  const mrrSeries = months.map((m, i) => ({ m, orgpuls: 118000 + i * 6400 + int(-2000, 2500), skiftly: 22000 + i * 3100 + int(-1500, 1500), avvik: i < 2 ? 0 : 4000 + (i - 2) * 1700, kurs: i < 8 ? 0 : (i - 7) * 600 }));
  const notifications = [
    { kind: 'Mentions', t: 'Ingrid mentioned you on Lumio AS — Expansion to Skiftly', s: '«@Tor can we offer the partner discount here?»', ago: '8 min', route: 'deals' },
    { kind: 'Reminders', t: 'Call Kari Nordmann in 15 minutes', s: 'Follow-up call · Lumio AS', ago: 'now', route: 'activities' },
    { kind: 'Security', t: 'New device sign-in for Hanna Vik', s: 'Edge on Windows 11 · Bergen, NO', ago: '32 min', route: 'security' },
    { kind: 'All', t: 'Nordvik Anlegg AS moved to Negotiation', s: 'You follow this deal · by Eirik Moen', ago: '1 h', route: 'deals' },
    { kind: 'All', t: 'T-2310 is close to breaching first response', s: 'Urgent · 38 min left', ago: '1 h', route: 'tickets' },
    { kind: 'All', t: 'Workflow «Trial day 7 — no survey» failed 3 times', s: 'Step 4 · webhook timeout', ago: '2 h', route: 'automation' },
  ];
  window.SA = { ICON, products, productById: Object.fromEntries(products.map((p) => [p.id, p])), staff, staffById, bands, industries, fylker, sources, orgs, orgById, people, personById, pipelines, labelDefs, deals, activities, actTypes, tickets, settings, months, mrrSeries, notifications, today, nb, kr, pct, rnd, int, pick };
})();
