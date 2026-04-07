<!--
  ============================================================
  DPI Society — Supabase Connection Library
  Save this as: supabase.js
  
  HOW TO USE:
  Add this ONE line to the <head> of every HTML page:
  <script src="supabase.js"></script>

  Then use window.sb to access Supabase anywhere:
  const { data, error } = await window.sb.from('profiles').select('*')
  ============================================================
-->

<script>
// ── YOUR SUPABASE CREDENTIALS ──
// Replace these two values with your own from:
// Supabase Dashboard → Settings → API
const SUPABASE_URL  = 'YOUR_SUPABASE_URL_HERE';   // e.g. https://abcdefgh.supabase.co
const SUPABASE_KEY  = 'YOUR_SUPABASE_ANON_KEY_HERE'; // starts with eyJ...

// ── LOAD SUPABASE SDK & INIT ──
(function() {
  const script = document.createElement('script');
  script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
  script.onload = function() {
    window.sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    window.dispatchEvent(new Event('supabase-ready'));
    console.log('%c✅ DPI Society — Supabase connected', 'color:#006A4E;font-weight:bold;');
  };
  document.head.appendChild(script);
})();

// ── AUTH HELPERS ──
window.DPI = {

  // Get currently logged-in user
  async getUser() {
    const { data: { user } } = await window.sb.auth.getUser();
    return user;
  },

  // Get user profile from profiles table
  async getProfile(userId) {
    const { data, error } = await window.sb
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();
    return data;
  },

  // Register a new member
  async register({ email, password, fullName, batch, department, phone, location, profession, bio, userType }) {
    const { data, error } = await window.sb.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName }
      }
    });
    if (error) return { error };

    // Update profile with additional info
    if (data.user) {
      await window.sb.from('profiles').update({
        full_name:   fullName,
        batch:       batch,
        department:  department,
        phone:       phone,
        location:    location,
        profession:  profession,
        bio:         bio,
        user_type:   userType || 'member',
        status:      'pending'
      }).eq('id', data.user.id);
    }
    return { data };
  },

  // Log in
  async login(email, password) {
    const { data, error } = await window.sb.auth.signInWithPassword({ email, password });
    return { data, error };
  },

  // Log out
  async logout() {
    await window.sb.auth.signOut();
    window.location.href = 'login.html';
  },

  // Check if logged in — redirect to login if not
  async requireAuth() {
    const user = await this.getUser();
    if (!user) {
      window.location.href = 'login.html?redirect=' + encodeURIComponent(window.location.pathname);
    }
    return user;
  },

  // Check if admin
  async requireAdmin() {
    const user = await this.getUser();
    if (!user) { window.location.href = 'login.html'; return; }
    const profile = await this.getProfile(user.id);
    if (!profile || profile.user_type !== 'admin') {
      alert('Access denied. Admin only.');
      window.location.href = 'index.html';
    }
    return { user, profile };
  },

  // ── MEMBERS ──
  async getMembers({ search, department, batch, limit = 24, page = 0 } = {}) {
    let query = window.sb
      .from('profiles')
      .select('*', { count: 'exact' })
      .eq('status', 'active')
      .order('created_at', { ascending: false })
      .range(page * limit, (page + 1) * limit - 1);
    if (search)     query = query.ilike('full_name', `%${search}%`);
    if (department) query = query.eq('department', department);
    if (batch)      query = query.eq('batch', batch);
    return await query;
  },

  // ── FORUM POSTS ──
  async getPosts({ category, search, sort = 'created_at', limit = 20 } = {}) {
    let query = window.sb
      .from('posts_with_details')
      .select('*')
      .order(sort, { ascending: false })
      .limit(limit);
    if (category && category !== 'all') query = query.eq('category', category);
    if (search) query = query.ilike('title', `%${search}%`);
    return await query;
  },

  async getPost(id) {
    return await window.sb
      .from('posts_with_details')
      .select('*')
      .eq('id', id)
      .single();
  },

  async createPost({ title, body, category, tags }) {
    const user = await this.getUser();
    if (!user) return { error: { message: 'Not logged in' } };
    return await window.sb.from('posts').insert({
      author_id: user.id,
      title, body, category, tags
    }).select().single();
  },

  async votePost(postId) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };
    const { data: existing } = await window.sb
      .from('votes').select('id').eq('post_id', postId).eq('user_id', user.id).single();
    if (existing) {
      return await window.sb.from('votes').delete().eq('post_id', postId).eq('user_id', user.id);
    } else {
      return await window.sb.from('votes').insert({ post_id: postId, user_id: user.id });
    }
  },

  async incrementViews(postId) {
    await window.sb.rpc('increment_views', { post_id: postId });
  },

  // ── REPLIES ──
  async getReplies(postId) {
    return await window.sb
      .from('replies')
      .select('*, profiles(full_name, batch, avatar_url)')
      .eq('post_id', postId)
      .eq('status', 'active')
      .order('created_at', { ascending: true });
  },

  async createReply({ postId, body }) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };
    return await window.sb.from('replies').insert({
      post_id: postId, author_id: user.id, body
    }).select().single();
  },

  async likeReply(replyId) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };
    const { data: existing } = await window.sb
      .from('reply_likes').select('id').eq('reply_id', replyId).eq('user_id', user.id).single();
    if (existing) {
      return await window.sb.from('reply_likes').delete().eq('reply_id', replyId).eq('user_id', user.id);
    } else {
      return await window.sb.from('reply_likes').insert({ reply_id: replyId, user_id: user.id });
    }
  },

  // ── RESOURCES ──
  async getResources({ search, department, fileType, sort = 'created_at', limit = 36 } = {}) {
    let query = window.sb
      .from('resources_with_uploader')
      .select('*')
      .order(sort === 'popular' ? 'downloads' : 'created_at', { ascending: false })
      .limit(limit);
    if (search)     query = query.ilike('title', `%${search}%`);
    if (department) query = query.eq('department', department);
    if (fileType && fileType !== 'all') query = query.eq('file_type', fileType);
    return await query;
  },

  async uploadResource({ title, description, department, contentType, fileType, tags }, file) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };

    let fileUrl = null;
    if (file) {
      const path = `resources/${user.id}/${Date.now()}-${file.name}`;
      const { data: upload, error: uploadErr } = await window.sb.storage
        .from('resources').upload(path, file);
      if (uploadErr) return { error: uploadErr };
      const { data: { publicUrl } } = window.sb.storage.from('resources').getPublicUrl(path);
      fileUrl = publicUrl;
    }

    return await window.sb.from('resources').insert({
      uploader_id:  user.id,
      title, description, department,
      content_type: contentType,
      file_type:    fileType,
      file_url:     fileUrl,
      file_size:    file ? (file.size / 1024 / 1024).toFixed(1) + ' MB' : '—',
      tags:         tags,
      status:       'review'
    }).select().single();
  },

  async downloadResource(resourceId) {
    await window.sb.rpc('increment_downloads', { resource_id: resourceId });
  },

  async toggleSaveResource(resourceId) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };
    const { data: existing } = await window.sb
      .from('saved_resources').select('id').eq('resource_id', resourceId).eq('user_id', user.id).single();
    if (existing) {
      return await window.sb.from('saved_resources').delete().eq('resource_id', resourceId).eq('user_id', user.id);
    } else {
      return await window.sb.from('saved_resources').insert({ resource_id: resourceId, user_id: user.id });
    }
  },

  // ── EVENTS ──
  async getEvents({ status } = {}) {
    let query = window.sb
      .from('events_with_rsvp_count')
      .select('*')
      .order('event_date', { ascending: true });
    if (status) query = query.eq('status', status);
    return await query;
  },

  async toggleRSVP(eventId) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };
    const { data: existing } = await window.sb
      .from('rsvps').select('id').eq('event_id', eventId).eq('user_id', user.id).single();
    if (existing) {
      return await window.sb.from('rsvps').delete().eq('event_id', eventId).eq('user_id', user.id);
    } else {
      return await window.sb.from('rsvps').insert({ event_id: eventId, user_id: user.id });
    }
  },

  async getUserRSVPs() {
    const user = await this.getUser();
    if (!user) return { data: [] };
    return await window.sb.from('rsvps').select('event_id').eq('user_id', user.id);
  },

  // ── PROFILE UPDATE ──
  async updateProfile(updates) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };
    return await window.sb.from('profiles')
      .update({ ...updates, updated_at: new Date().toISOString() })
      .eq('id', user.id);
  },

  // ── UPLOAD AVATAR ──
  async uploadAvatar(file) {
    const user = await this.getUser();
    if (!user) return { error: 'Not logged in' };
    const path = `avatars/${user.id}`;
    await window.sb.storage.from('avatars').upload(path, file, { upsert: true });
    const { data: { publicUrl } } = window.sb.storage.from('avatars').getPublicUrl(path);
    await this.updateProfile({ avatar_url: publicUrl });
    return { url: publicUrl };
  },

  // ── ADMIN: stats ──
  async getAdminStats() {
    const [members, posts, resources, events] = await Promise.all([
      window.sb.from('profiles').select('*', { count: 'exact', head: true }),
      window.sb.from('posts').select('*', { count: 'exact', head: true }),
      window.sb.from('resources').select('*', { count: 'exact', head: true }),
      window.sb.from('events').select('*', { count: 'exact', head: true }),
    ]);
    return {
      members:   members.count,
      posts:     posts.count,
      resources: resources.count,
      events:    events.count,
    };
  },

  // ── ADMIN: approve member ──
  async approveMember(userId) {
    return await window.sb.from('profiles')
      .update({ status: 'active' }).eq('id', userId);
  },

  // ── ADMIN: approve resource ──
  async approveResource(resourceId) {
    return await window.sb.from('resources')
      .update({ status: 'approved' }).eq('id', resourceId);
  },

  // ── REALTIME: subscribe to new posts ──
  subscribeToNewPosts(callback) {
    return window.sb
      .channel('public:posts')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'posts' }, callback)
      .subscribe();
  },

  // ── REALTIME: subscribe to new replies ──
  subscribeToReplies(postId, callback) {
    return window.sb
      .channel('replies:' + postId)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'replies',
        filter: `post_id=eq.${postId}`
      }, callback)
      .subscribe();
  },
};
</script>
