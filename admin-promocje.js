(() => {
  const API = 'https://api.gymprogres.pl/api/v1';
  const TOKEN_KEY = 'gymprogres_admin_promo_access';
  let token = sessionStorage.getItem(TOKEN_KEY) || '';
  let selectedUser = null;
  let currentPromotion = null;

  const $ = (id) => document.getElementById(id);
  const loginCard = $('loginCard');
  const adminCard = $('adminCard');
  const promotionCard = $('promotionCard');
  const logoutButton = $('logoutButton');
  const usersBox = $('users');

  const plans = {
    personal: [{ code: 'personal', label: 'Personal Pro' }],
    trainer: [
      { code: 'trainer_start', label: 'Trener Start — limit 5' },
      { code: 'trainer_pro', label: 'Trener Pro — limit 15' },
      { code: 'trainer_pro_plus', label: 'Trener Pro+ — limit 30' },
      { code: 'trainer_studio', label: 'Trener Studio — limit 50' }
    ]
  };

  function message(target, text, kind = 'error') {
    target.textContent = '';
    if (!text) return;
    const box = document.createElement('div');
    box.className = kind === 'success' ? 'success' : 'error';
    box.textContent = text;
    target.appendChild(box);
  }

  function formatDate(value) {
    if (!value) return 'bezterminowo';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return new Intl.DateTimeFormat('pl-PL', {
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit'
    }).format(date);
  }

  async function request(path, options = {}) {
    const headers = {
      'Content-Type': 'application/json',
      'X-GymProgres-Platform': 'web',
      'X-GymProgres-App-Version': 'web-admin-promo-1',
      ...(options.headers || {})
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(`${API}${path}`, { ...options, headers });
    let data = null;
    try { data = await response.json(); } catch (_) { data = null; }
    if (!response.ok) {
      if (response.status === 401) clearSession(false);
      const detail = data && data.detail;
      let text = 'Nie udało się wykonać operacji.';
      if (typeof detail === 'string') text = detail;
      else if (Array.isArray(detail) && detail.length) text = detail.map((item) => item.msg || String(item)).join(' ');
      throw new Error(text);
    }
    return data;
  }

  function setBusy(section, busy) {
    section.classList.toggle('loading', busy);
    section.querySelectorAll('button,input,select,textarea').forEach((el) => {
      if (el.id !== 'closeUserButton') el.disabled = busy;
    });
  }

  function clearSession(showLogin = true) {
    token = '';
    sessionStorage.removeItem(TOKEN_KEY);
    selectedUser = null;
    currentPromotion = null;
    adminCard.classList.add('hidden');
    promotionCard.classList.add('hidden');
    logoutButton.classList.add('hidden');
    if (showLogin) loginCard.classList.remove('hidden');
  }

  async function verifySession() {
    if (!token) return false;
    try {
      const me = await request('/auth/me');
      if (!me || me.role !== 'admin') throw new Error('To konto nie ma uprawnień administratora.');
      loginCard.classList.add('hidden');
      adminCard.classList.remove('hidden');
      logoutButton.classList.remove('hidden');
      await loadUsers('');
      return true;
    } catch (error) {
      clearSession(true);
      message($('loginMessage'), error.message);
      return false;
    }
  }

  $('loginForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    message($('loginMessage'), '');
    setBusy(loginCard, true);
    try {
      const data = await fetch(`${API}/auth/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-GymProgres-Platform': 'web',
          'X-GymProgres-App-Version': 'web-admin-promo-1'
        },
        body: JSON.stringify({
          login: $('login').value.trim(),
          password: $('password').value,
          device_name: 'Web Admin — promocje'
        })
      });
      const body = await data.json().catch(() => ({}));
      if (!data.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Nieprawidłowy login lub hasło.');
      if (!body.user || body.user.role !== 'admin') throw new Error('To konto nie ma uprawnień administratora.');
      token = body.access_token || '';
      if (!token) throw new Error('Serwer nie zwrócił tokenu sesji.');
      sessionStorage.setItem(TOKEN_KEY, token);
      $('password').value = '';
      loginCard.classList.add('hidden');
      adminCard.classList.remove('hidden');
      logoutButton.classList.remove('hidden');
      await loadUsers('');
    } catch (error) {
      token = '';
      sessionStorage.removeItem(TOKEN_KEY);
      message($('loginMessage'), error.message);
    } finally {
      setBusy(loginCard, false);
    }
  });

  logoutButton.addEventListener('click', () => clearSession(true));

  $('searchForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    await loadUsers($('search').value.trim());
  });

  async function loadUsers(query) {
    message($('adminMessage'), '');
    usersBox.textContent = '';
    setBusy(adminCard, true);
    try {
      const params = new URLSearchParams({ include_admins: 'false' });
      if (query) params.set('query', query);
      const users = await request(`/admin/users?${params}`);
      if (!Array.isArray(users) || users.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'muted';
        empty.textContent = 'Nie znaleziono użytkowników.';
        usersBox.appendChild(empty);
        return;
      }
      users.forEach(renderUser);
    } catch (error) {
      message($('adminMessage'), error.message);
    } finally {
      setBusy(adminCard, false);
    }
  }

  function renderUser(user) {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'user';
    item.style.width = '100%';
    item.style.color = 'inherit';
    item.style.textAlign = 'left';
    item.style.font = 'inherit';

    const info = document.createElement('div');
    const title = document.createElement('strong');
    title.textContent = user.display_name || user.login;
    const details = document.createElement('small');
    details.textContent = `${user.login} • ${user.role} • ${user.plan_name || 'brak planu'} • ${user.subscription_status || 'brak subskrypcji'}`;
    info.append(title, details);

    const badge = document.createElement('span');
    badge.className = 'badge';
    badge.textContent = user.role === 'trener' ? `Trener ${user.trainee_count || 0}/${user.effective_trainee_limit || 0}` : 'Użytkownik';

    item.append(info, badge);
    item.addEventListener('click', () => openUser(user));
    usersBox.appendChild(item);
  }

  async function openUser(user) {
    selectedUser = user;
    currentPromotion = null;
    promotionCard.classList.remove('hidden');
    $('promotionTitle').textContent = `Dostęp promocyjny • ${user.display_name || user.login}`;
    $('reason').value = '';
    $('days').value = '30';
    $('indefinite').checked = false;
    $('daysWrap').classList.remove('hidden');
    fillPlans(user.role);
    message($('promotionMessage'), '');
    renderCurrentPromotion();
    setBusy(promotionCard, true);
    try {
      const result = await request(`/admin/users/${encodeURIComponent(user.login)}/promotion`);
      currentPromotion = result && result.promotion ? result.promotion : null;
      renderCurrentPromotion();
      promotionCard.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (error) {
      message($('promotionMessage'), error.message);
    } finally {
      setBusy(promotionCard, false);
    }
  }

  function fillPlans(role) {
    const select = $('plan');
    select.textContent = '';
    const options = role === 'trener' ? plans.trainer : plans.personal;
    options.forEach((item) => {
      const option = document.createElement('option');
      option.value = item.code;
      option.textContent = item.label;
      select.appendChild(option);
    });
  }

  function renderCurrentPromotion() {
    const box = $('currentPromotion');
    box.textContent = '';
    const revoke = $('revokeButton');
    const grant = $('grantButton');
    if (!currentPromotion) {
      const text = document.createElement('p');
      text.className = 'muted';
      text.textContent = 'Brak aktywnego dostępu promocyjnego.';
      box.appendChild(text);
      revoke.classList.add('hidden');
      grant.textContent = 'Nadaj dostęp';
      return;
    }
    const wrap = document.createElement('div');
    wrap.className = 'promo-current';
    const strong = document.createElement('strong');
    strong.textContent = 'Aktywny dostęp promocyjny';
    const line = document.createElement('div');
    line.textContent = `${currentPromotion.plan_name || currentPromotion.plan_code} • do ${formatDate(currentPromotion.expires_at)}`;
    wrap.append(strong, line);
    if (currentPromotion.reason) {
      const reason = document.createElement('div');
      reason.className = 'muted';
      reason.textContent = `Powód: ${currentPromotion.reason}`;
      wrap.appendChild(reason);
    }
    box.appendChild(wrap);
    revoke.classList.remove('hidden');
    grant.textContent = 'Zmień promocję';
    const available = [...$('plan').options].some((opt) => opt.value === currentPromotion.plan_code);
    if (available) $('plan').value = currentPromotion.plan_code;
  }

  $('indefinite').addEventListener('change', () => {
    $('daysWrap').classList.toggle('hidden', $('indefinite').checked);
  });

  $('promotionForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!selectedUser) return;
    const reason = $('reason').value.trim();
    const indefinite = $('indefinite').checked;
    const days = indefinite ? null : Number.parseInt($('days').value, 10);
    if (reason.length < 3) {
      message($('promotionMessage'), 'Podaj powód promocji (minimum 3 znaki).');
      return;
    }
    if (!indefinite && (!Number.isInteger(days) || days < 1 || days > 3650)) {
      message($('promotionMessage'), 'Podaj liczbę dni od 1 do 3650 albo wybierz dostęp bezterminowy.');
      return;
    }
    setBusy(promotionCard, true);
    message($('promotionMessage'), '');
    try {
      const result = await request(`/admin/users/${encodeURIComponent(selectedUser.login)}/promotion`, {
        method: 'POST',
        body: JSON.stringify({ plan_code: $('plan').value, days, reason })
      });
      currentPromotion = result && result.promotion ? result.promotion : null;
      renderCurrentPromotion();
      message($('promotionMessage'), 'Dostęp promocyjny został zapisany.', 'success');
      await loadUsers($('search').value.trim());
    } catch (error) {
      message($('promotionMessage'), error.message);
    } finally {
      setBusy(promotionCard, false);
    }
  });

  $('revokeButton').addEventListener('click', async () => {
    if (!selectedUser || !currentPromotion) return;
    const reason = $('reason').value.trim();
    if (reason.length < 3) {
      message($('promotionMessage'), 'Wpisz powód odebrania promocji w polu powodu.');
      return;
    }
    if (!window.confirm(`Odebrać dostęp promocyjny użytkownikowi ${selectedUser.login}?`)) return;
    setBusy(promotionCard, true);
    message($('promotionMessage'), '');
    try {
      await request(`/admin/users/${encodeURIComponent(selectedUser.login)}/promotion`, {
        method: 'DELETE',
        body: JSON.stringify({ reason })
      });
      currentPromotion = null;
      renderCurrentPromotion();
      message($('promotionMessage'), 'Dostęp promocyjny został odebrany.', 'success');
      await loadUsers($('search').value.trim());
    } catch (error) {
      message($('promotionMessage'), error.message);
    } finally {
      setBusy(promotionCard, false);
    }
  });

  $('closeUserButton').addEventListener('click', () => {
    selectedUser = null;
    currentPromotion = null;
    promotionCard.classList.add('hidden');
  });

  verifySession();
})();
