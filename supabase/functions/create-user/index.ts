import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

serve(async (req) => {
  try {
    if (req.method !== "POST") return new Response("Method not allowed", { status:405 });

    const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
    if (!jwt) return new Response(JSON.stringify({message:"missing auth"}), { status:401 });

    const userClient = createClient(SUPABASE_URL, jwt);
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return new Response(JSON.stringify({message:"not logged"}), { status:401 });

    const me = await userClient.from("v2.perfis").select("role").eq("user_id", user.id).maybeSingle();
    if (me.data?.role !== "MASTER") return new Response(JSON.stringify({message:"only MASTER"}), { status:403 });

    const { email, password, role, school_id, turmas } = await req.json();
    if (!email || !password || !role || !school_id) return new Response(JSON.stringify({message:"email/password/role/school_id required"}), { status:400 });
    if (!["SCHOOL_ADMIN","TEACHER"].includes(role)) return new Response(JSON.stringify({message:"invalid role"}), { status:400 });

    const list = await admin.auth.admin.listUsers({ page:1, perPage:200 });
    const found = list.data.users.find(u => u.email === email);
    let uid: string;
    if (found) { uid = found.id; }
    else {
      const created = await admin.auth.admin.createUser({ email, password, email_confirm:true });
      if (created.error) return new Response(JSON.stringify({message:created.error.message}), { status:400 });
      uid = created.data.user!.id;
    }

    const perf = await admin.from("v2.perfis").upsert({ user_id: uid, role, school_id }, { onConflict: "user_id" });
    if (perf.error) return new Response(JSON.stringify({message:perf.error.message}), { status:400 });

    if (role === "TEACHER" && Array.isArray(turmas) && turmas.length) {
      const rows = turmas.map((t:string)=>({ id_professor: uid, id_escola: school_id, id_turma: t }));
      const v = await admin.from("v2.professores").upsert(rows, { onConflict: "id_professor,id_escola,id_turma" });
      if (v.error) return new Response(JSON.stringify({message:v.error.message}), { status:400 });
    }

    return new Response(JSON.stringify({ ok:true, user_id: uid }), { status:200, headers:{ "Content-Type":"application/json" }});
  } catch (e) {
    return new Response(JSON.stringify({message: e?.message || String(e)}), { status:500 });
  }
});
