-- The account behind the app's one-tap demo login (AuthController.demoEmail /
-- demoPassword). Created already confirmed, so it works without an inbox.
-- Safe to run more than once. The sign-up trigger creates its profile,
-- settings and progress rows.

do $$
declare
  demo_id uuid;
begin
  select id into demo_id from auth.users where email = 'demo.traveler@urbanpulse.ai';
  if demo_id is not null then
    return;
  end if;

  demo_id := gen_random_uuid();
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', demo_id, 'authenticated', 'authenticated',
    'demo.traveler@urbanpulse.ai', crypt('urbanpulse2026', gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    '{"full_name": "Demo Explorer"}'::jsonb,
    now(), now(), '', '', '', ''
  );
  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), demo_id, demo_id::text,
    jsonb_build_object('sub', demo_id::text, 'email', 'demo.traveler@urbanpulse.ai', 'email_verified', true),
    'email', now(), now(), now()
  );
end;
$$;
