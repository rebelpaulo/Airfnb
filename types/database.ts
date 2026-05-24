/* Auto-generated from Supabase airfnb_* schema. Re-run via: pnpm types:gen
 *
 * Note: the generator initially emits `Database["public"]["Enums"][…]` references
 * inside the table bodies (because the original Supabase generator names its root
 * interface `Database`). We expose a `Database` alias below so those references
 * resolve without rewriting every column type.
 */
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

/* ------- Marketplace row types (used by Tables block below) ------- */

export interface AirfnbEventRequestRow {
  id: string;
  organizer_id: string;
  title: string;
  kind:
    | "wedding" | "birthday" | "corporate" | "festival"
    | "conference" | "private" | "other"
    | null;
  description: string | null;
  start_at: string;
  end_at: string | null;
  city: string | null;
  address_id: string | null;
  expected_pax: number;
  slots_needed: number;
  budget_min: number | null;
  budget_max: number | null;
  desired_categories: number[];
  dietary_requirements: Array<
    | "vegan" | "vegetarian" | "gluten_free" | "lactose_free"
    | "nut_free" | "halal" | "kosher" | "spicy"
  >;
  applications_deadline: string | null;
  power_available: boolean;
  water_available: boolean;
  notes: string | null;
  status: "draft" | "open" | "reviewing" | "awarded" | "closed" | "expired" | "cancelled";
  visibility: "public" | "invite_only";
  awarded_at: string | null;
  created_at: string;
  updated_at: string;
  discovery_mode: "curated" | "broadcast" | "auto_match";
  accepted_deal_types: string[];
  min_fixed_fee: number | null;
  min_revenue_share_pct: number | null;
  recommended_slots: number | null;
  slot_breakdown: Json | null;
  application_response_window_hours: number;
}

export interface AirfnbApplicationRow {
  id: string;
  request_id: string;
  truck_id: string;
  proposed_price: number;
  cover_message: string | null;
  menu_pitch: Json | null;
  estimated_servings: number | null;
  available_confirmed: boolean;
  status: "submitted" | "shortlisted" | "accepted" | "rejected" | "withdrawn" | "expired";
  shortlisted_at: string | null;
  decided_at: string | null;
  withdrawn_at: string | null;
  created_at: string;
  updated_at: string;
  deal_type: "fixed" | "percent" | "mixed";
  proposed_fixed_to_organizer: number;
  proposed_revenue_share_pct: number;
}

export interface AirfnbLockFeeRow {
  id: string;
  application_id: string;
  amount: number;
  currency: string;
  due_until: string;
  status: "pending" | "paid" | "expired" | "refunded" | "waived";
  paid_at: string | null;
  provider_ref: string | null;
  refunded_at: string | null;
  created_at: string;
  platform_fee: number;
  organizer_share: number;
}

export interface AirfnbRequestInvitationRow {
  request_id: string;
  truck_id: string;
  invited_by: string | null;
  invited_at: string;
  responded: boolean;
}

export interface AirfnbTruckAlertPrefRow {
  truck_id: string;
  cities: string[];
  category_ids: number[];
  min_budget: number | null;
  max_radius_km: number | null;
  channels: Json;
  updated_at: string;
}

export interface AirfnbDatabase {
  public: {
    Tables: {
      airfnb_addresses: {
        Row: {
          city: string | null
          country: string | null
          created_at: string | null
          geom: unknown
          id: string
          label: string | null
          line1: string
          line2: string | null
          owner_id: string | null
          postal_code: string | null
          region: string | null
        }
        Insert: {
          city?: string | null
          country?: string | null
          created_at?: string | null
          geom?: unknown
          id?: string
          label?: string | null
          line1: string
          line2?: string | null
          owner_id?: string | null
          postal_code?: string | null
          region?: string | null
        }
        Update: {
          city?: string | null
          country?: string | null
          created_at?: string | null
          geom?: unknown
          id?: string
          label?: string | null
          line1?: string
          line2?: string | null
          owner_id?: string | null
          postal_code?: string | null
          region?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_addresses_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_audit_log: {
        Row: {
          action: string | null
          actor_id: string | null
          created_at: string | null
          diff: Json | null
          entity: string | null
          entity_id: string | null
          id: number
          ip: unknown
        }
        Insert: {
          action?: string | null
          actor_id?: string | null
          created_at?: string | null
          diff?: Json | null
          entity?: string | null
          entity_id?: string | null
          id?: number
          ip?: unknown
        }
        Update: {
          action?: string | null
          actor_id?: string | null
          created_at?: string | null
          diff?: Json | null
          entity?: string | null
          entity_id?: string | null
          id?: number
          ip?: unknown
        }
        Relationships: []
      }
      airfnb_blog_authors: {
        Row: {
          bio: string | null
          id: string
          instagram: string | null
          twitter: string | null
        }
        Insert: {
          bio?: string | null
          id: string
          instagram?: string | null
          twitter?: string | null
        }
        Update: {
          bio?: string | null
          id?: string
          instagram?: string | null
          twitter?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_blog_authors_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_blog_categories: {
        Row: {
          id: number
          name: string
          slug: string
        }
        Insert: {
          id?: number
          name: string
          slug: string
        }
        Update: {
          id?: number
          name?: string
          slug?: string
        }
        Relationships: []
      }
      airfnb_blog_posts: {
        Row: {
          author_id: string | null
          body_md: string | null
          category_id: number | null
          cover_url: string | null
          created_at: string | null
          excerpt: string | null
          id: string
          published_at: string | null
          read_minutes: number | null
          seo_description: string | null
          seo_title: string | null
          slug: string
          status: Database["public"]["Enums"]["airfnb_post_status"] | null
          title: string
        }
        Insert: {
          author_id?: string | null
          body_md?: string | null
          category_id?: number | null
          cover_url?: string | null
          created_at?: string | null
          excerpt?: string | null
          id?: string
          published_at?: string | null
          read_minutes?: number | null
          seo_description?: string | null
          seo_title?: string | null
          slug: string
          status?: Database["public"]["Enums"]["airfnb_post_status"] | null
          title: string
        }
        Update: {
          author_id?: string | null
          body_md?: string | null
          category_id?: number | null
          cover_url?: string | null
          created_at?: string | null
          excerpt?: string | null
          id?: string
          published_at?: string | null
          read_minutes?: number | null
          seo_description?: string | null
          seo_title?: string | null
          slug?: string
          status?: Database["public"]["Enums"]["airfnb_post_status"] | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_blog_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "airfnb_blog_authors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_blog_posts_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "airfnb_blog_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_booking_addons: {
        Row: {
          booking_id: string | null
          description: string | null
          id: string
          provider_id: string | null
          qty: number | null
          unit_price: number | null
        }
        Insert: {
          booking_id?: string | null
          description?: string | null
          id?: string
          provider_id?: string | null
          qty?: number | null
          unit_price?: number | null
        }
        Update: {
          booking_id?: string | null
          description?: string | null
          id?: string
          provider_id?: string | null
          qty?: number | null
          unit_price?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_booking_addons_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_booking_addons_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_booking_addons_provider_id_fkey"
            columns: ["provider_id"]
            isOneToOne: false
            referencedRelation: "airfnb_service_providers"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_booking_trucks: {
        Row: {
          agreed_price: number | null
          booking_id: string
          notes: string | null
          truck_id: string
        }
        Insert: {
          agreed_price?: number | null
          booking_id: string
          notes?: string | null
          truck_id: string
        }
        Update: {
          agreed_price?: number | null
          booking_id?: string
          notes?: string | null
          truck_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_booking_trucks_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_booking_trucks_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_booking_trucks_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_booking_trucks_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_bookings: {
        Row: {
          cancellation_reason: string | null
          created_at: string | null
          currency: string | null
          ends_at: string | null
          event_id: string | null
          id: string
          notes: string | null
          organizer_id: string | null
          pax_count: number | null
          starts_at: string | null
          status: Database["public"]["Enums"]["airfnb_booking_status"] | null
          total_amount: number | null
          updated_at: string | null
        }
        Insert: {
          cancellation_reason?: string | null
          created_at?: string | null
          currency?: string | null
          ends_at?: string | null
          event_id?: string | null
          id?: string
          notes?: string | null
          organizer_id?: string | null
          pax_count?: number | null
          starts_at?: string | null
          status?: Database["public"]["Enums"]["airfnb_booking_status"] | null
          total_amount?: number | null
          updated_at?: string | null
        }
        Update: {
          cancellation_reason?: string | null
          created_at?: string | null
          currency?: string | null
          ends_at?: string | null
          event_id?: string | null
          id?: string
          notes?: string | null
          organizer_id?: string | null
          pax_count?: number | null
          starts_at?: string | null
          status?: Database["public"]["Enums"]["airfnb_booking_status"] | null
          total_amount?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_bookings_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "airfnb_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_bookings_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["event_id"]
          },
          {
            foreignKeyName: "airfnb_bookings_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_categories: {
        Row: {
          icon: string | null
          id: number
          name_en: string | null
          name_pt: string
          slug: string
        }
        Insert: {
          icon?: string | null
          id?: number
          name_en?: string | null
          name_pt: string
          slug: string
        }
        Update: {
          icon?: string | null
          id?: number
          name_en?: string | null
          name_pt?: string
          slug?: string
        }
        Relationships: []
      }
      airfnb_contact_requests: {
        Row: {
          created_at: string | null
          email: string | null
          handled_by: string | null
          id: string
          message: string | null
          name: string | null
          phone: string | null
          source_page: string | null
        }
        Insert: {
          created_at?: string | null
          email?: string | null
          handled_by?: string | null
          id?: string
          message?: string | null
          name?: string | null
          phone?: string | null
          source_page?: string | null
        }
        Update: {
          created_at?: string | null
          email?: string | null
          handled_by?: string | null
          id?: string
          message?: string | null
          name?: string | null
          phone?: string | null
          source_page?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_contact_requests_handled_by_fkey"
            columns: ["handled_by"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_conversation_participants: {
        Row: {
          conversation_id: string
          last_read_at: string | null
          user_id: string
        }
        Insert: {
          conversation_id: string
          last_read_at?: string | null
          user_id: string
        }
        Update: {
          conversation_id?: string
          last_read_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_conversation_participants_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "airfnb_conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_conversation_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_conversations: {
        Row: {
          booking_id: string | null
          created_at: string | null
          id: string
        }
        Insert: {
          booking_id?: string | null
          created_at?: string | null
          id?: string
        }
        Update: {
          booking_id?: string | null
          created_at?: string | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_conversations_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_conversations_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_events: {
        Row: {
          address_id: string | null
          budget_max: number | null
          budget_min: number | null
          city: string | null
          created_at: string | null
          end_at: string | null
          expected_pax: number | null
          id: string
          kind: Database["public"]["Enums"]["airfnb_event_kind"] | null
          notes: string | null
          organizer_id: string
          start_at: string | null
          status: string | null
          title: string | null
        }
        Insert: {
          address_id?: string | null
          budget_max?: number | null
          budget_min?: number | null
          city?: string | null
          created_at?: string | null
          end_at?: string | null
          expected_pax?: number | null
          id?: string
          kind?: Database["public"]["Enums"]["airfnb_event_kind"] | null
          notes?: string | null
          organizer_id: string
          start_at?: string | null
          status?: string | null
          title?: string | null
        }
        Update: {
          address_id?: string | null
          budget_max?: number | null
          budget_min?: number | null
          city?: string | null
          created_at?: string | null
          end_at?: string | null
          expected_pax?: number | null
          id?: string
          kind?: Database["public"]["Enums"]["airfnb_event_kind"] | null
          notes?: string | null
          organizer_id?: string
          start_at?: string | null
          status?: string | null
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_events_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "airfnb_addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_events_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_faqs: {
        Row: {
          answer: string
          id: number
          question: string
          sort_order: number | null
          topic: string | null
        }
        Insert: {
          answer: string
          id?: number
          question: string
          sort_order?: number | null
          topic?: string | null
        }
        Update: {
          answer?: string
          id?: number
          question?: string
          sort_order?: number | null
          topic?: string | null
        }
        Relationships: []
      }
      airfnb_favorites: {
        Row: {
          created_at: string | null
          truck_id: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          truck_id: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          truck_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_favorites_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_favorites_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_favorites_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_invoices: {
        Row: {
          booking_id: string | null
          id: string
          issued_at: string | null
          number: string | null
          pdf_url: string | null
          total_amount: number | null
          vat_amount: number | null
        }
        Insert: {
          booking_id?: string | null
          id?: string
          issued_at?: string | null
          number?: string | null
          pdf_url?: string | null
          total_amount?: number | null
          vat_amount?: number | null
        }
        Update: {
          booking_id?: string | null
          id?: string
          issued_at?: string | null
          number?: string | null
          pdf_url?: string | null
          total_amount?: number | null
          vat_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_invoices_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_invoices_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_menu_items: {
        Row: {
          category: string | null
          description: string | null
          id: string
          image_url: string | null
          name: string
          price: number | null
          sort_order: number | null
          tags: Database["public"]["Enums"]["airfnb_dietary_tag"][] | null
          truck_id: string | null
        }
        Insert: {
          category?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          name: string
          price?: number | null
          sort_order?: number | null
          tags?: Database["public"]["Enums"]["airfnb_dietary_tag"][] | null
          truck_id?: string | null
        }
        Update: {
          category?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          name?: string
          price?: number | null
          sort_order?: number | null
          tags?: Database["public"]["Enums"]["airfnb_dietary_tag"][] | null
          truck_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_menu_items_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_menu_items_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_messages: {
        Row: {
          attachments: Json | null
          body: string | null
          conversation_id: string | null
          created_at: string | null
          id: string
          sender_id: string | null
        }
        Insert: {
          attachments?: Json | null
          body?: string | null
          conversation_id?: string | null
          created_at?: string | null
          id?: string
          sender_id?: string | null
        }
        Update: {
          attachments?: Json | null
          body?: string | null
          conversation_id?: string | null
          created_at?: string | null
          id?: string
          sender_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "airfnb_conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_newsletter_subscribers: {
        Row: {
          confirm_token: string | null
          confirmed: boolean | null
          created_at: string | null
          email: string
          id: string
        }
        Insert: {
          confirm_token?: string | null
          confirmed?: boolean | null
          created_at?: string | null
          email: string
          id?: string
        }
        Update: {
          confirm_token?: string | null
          confirmed?: boolean | null
          created_at?: string | null
          email?: string
          id?: string
        }
        Relationships: []
      }
      airfnb_notifications: {
        Row: {
          created_at: string | null
          id: string
          kind: string | null
          payload: Json | null
          read_at: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          kind?: string | null
          payload?: Json | null
          read_at?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          kind?: string | null
          payload?: Json | null
          read_at?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_payments: {
        Row: {
          amount: number | null
          booking_id: string | null
          created_at: string | null
          currency: string | null
          id: string
          method: Database["public"]["Enums"]["airfnb_payment_method"] | null
          paid_at: string | null
          provider_ref: string | null
          status: Database["public"]["Enums"]["airfnb_payment_status"] | null
        }
        Insert: {
          amount?: number | null
          booking_id?: string | null
          created_at?: string | null
          currency?: string | null
          id?: string
          method?: Database["public"]["Enums"]["airfnb_payment_method"] | null
          paid_at?: string | null
          provider_ref?: string | null
          status?: Database["public"]["Enums"]["airfnb_payment_status"] | null
        }
        Update: {
          amount?: number | null
          booking_id?: string | null
          created_at?: string | null
          currency?: string | null
          id?: string
          method?: Database["public"]["Enums"]["airfnb_payment_method"] | null
          paid_at?: string | null
          provider_ref?: string | null
          status?: Database["public"]["Enums"]["airfnb_payment_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_payments_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_payments_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_profiles: {
        Row: {
          avatar_url: string | null
          company_name: string | null
          created_at: string | null
          display_name: string | null
          full_name: string | null
          id: string
          locale: string | null
          marketing_opt_in: boolean | null
          phone: string | null
          role: Database["public"]["Enums"]["airfnb_user_role"]
          updated_at: string | null
          vat_number: string | null
        }
        Insert: {
          avatar_url?: string | null
          company_name?: string | null
          created_at?: string | null
          display_name?: string | null
          full_name?: string | null
          id: string
          locale?: string | null
          marketing_opt_in?: boolean | null
          phone?: string | null
          role?: Database["public"]["Enums"]["airfnb_user_role"]
          updated_at?: string | null
          vat_number?: string | null
        }
        Update: {
          avatar_url?: string | null
          company_name?: string | null
          created_at?: string | null
          display_name?: string | null
          full_name?: string | null
          id?: string
          locale?: string | null
          marketing_opt_in?: boolean | null
          phone?: string | null
          role?: Database["public"]["Enums"]["airfnb_user_role"]
          updated_at?: string | null
          vat_number?: string | null
        }
        Relationships: []
      }
      airfnb_proposals: {
        Row: {
          body: Json | null
          booking_id: string | null
          created_at: string | null
          id: string
          pdf_url: string | null
          prepared_by: string | null
          signed_at: string | null
          total_amount: number | null
          valid_until: string | null
          version: number | null
        }
        Insert: {
          body?: Json | null
          booking_id?: string | null
          created_at?: string | null
          id?: string
          pdf_url?: string | null
          prepared_by?: string | null
          signed_at?: string | null
          total_amount?: number | null
          valid_until?: string | null
          version?: number | null
        }
        Update: {
          body?: Json | null
          booking_id?: string | null
          created_at?: string | null
          id?: string
          pdf_url?: string | null
          prepared_by?: string | null
          signed_at?: string | null
          total_amount?: number | null
          valid_until?: string | null
          version?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_proposals_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_proposals_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_proposals_prepared_by_fkey"
            columns: ["prepared_by"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_reviews: {
        Row: {
          body: string | null
          booking_id: string | null
          created_at: string | null
          id: string
          is_verified: boolean | null
          organizer_id: string | null
          rating_food: number | null
          rating_overall: number | null
          rating_service: number | null
          rating_value: number | null
          reply_at: string | null
          reply_body: string | null
          truck_id: string | null
        }
        Insert: {
          body?: string | null
          booking_id?: string | null
          created_at?: string | null
          id?: string
          is_verified?: boolean | null
          organizer_id?: string | null
          rating_food?: number | null
          rating_overall?: number | null
          rating_service?: number | null
          rating_value?: number | null
          reply_at?: string | null
          reply_body?: string | null
          truck_id?: string | null
        }
        Update: {
          body?: string | null
          booking_id?: string | null
          created_at?: string | null
          id?: string
          is_verified?: boolean | null
          organizer_id?: string | null
          rating_food?: number | null
          rating_overall?: number | null
          rating_service?: number | null
          rating_value?: number | null
          reply_at?: string | null
          reply_body?: string | null
          truck_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_reviews_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_reviews_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_booking_full"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_reviews_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_reviews_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_reviews_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_service_providers: {
        Row: {
          city: string | null
          contact_email: string | null
          contact_phone: string | null
          created_at: string | null
          description: string | null
          id: string
          image_url: string | null
          kind: Database["public"]["Enums"]["airfnb_service_kind"] | null
          name: string | null
          price_from: number | null
        }
        Insert: {
          city?: string | null
          contact_email?: string | null
          contact_phone?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          kind?: Database["public"]["Enums"]["airfnb_service_kind"] | null
          name?: string | null
          price_from?: number | null
        }
        Update: {
          city?: string | null
          contact_email?: string | null
          contact_phone?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          kind?: Database["public"]["Enums"]["airfnb_service_kind"] | null
          name?: string | null
          price_from?: number | null
        }
        Relationships: []
      }
      airfnb_truck_availability: {
        Row: {
          booking_id: string | null
          date: string
          id: string
          status: string | null
          truck_id: string | null
        }
        Insert: {
          booking_id?: string | null
          date: string
          id?: string
          status?: string | null
          truck_id?: string | null
        }
        Update: {
          booking_id?: string | null
          date?: string
          id?: string
          status?: string | null
          truck_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_truck_availability_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_truck_availability_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_truck_categories: {
        Row: {
          category_id: number
          truck_id: string
        }
        Insert: {
          category_id: number
          truck_id: string
        }
        Update: {
          category_id?: number
          truck_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_truck_categories_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "airfnb_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_truck_categories_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_truck_categories_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_truck_documents: {
        Row: {
          expires_at: string | null
          id: string
          issued_at: string | null
          kind: string | null
          truck_id: string | null
          url: string | null
        }
        Insert: {
          expires_at?: string | null
          id?: string
          issued_at?: string | null
          kind?: string | null
          truck_id?: string | null
          url?: string | null
        }
        Update: {
          expires_at?: string | null
          id?: string
          issued_at?: string | null
          kind?: string | null
          truck_id?: string | null
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_truck_documents_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_truck_documents_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_truck_images: {
        Row: {
          alt: string | null
          id: string
          is_cover: boolean | null
          sort_order: number | null
          truck_id: string | null
          url: string
        }
        Insert: {
          alt?: string | null
          id?: string
          is_cover?: boolean | null
          sort_order?: number | null
          truck_id?: string | null
          url: string
        }
        Update: {
          alt?: string | null
          id?: string
          is_cover?: boolean | null
          sort_order?: number | null
          truck_id?: string | null
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_truck_images_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_trucks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "airfnb_truck_images_truck_id_fkey"
            columns: ["truck_id"]
            isOneToOne: false
            referencedRelation: "airfnb_v_truck_card"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_trucks: {
        Row: {
          base_city: string | null
          base_price: number | null
          capacity: number | null
          created_at: string | null
          description: string | null
          dimensions_m: number[] | null
          featured: boolean | null
          homologation_expires_at: string | null
          id: string
          insurance_expires_at: string | null
          max_event_pax: number | null
          min_event_pax: number | null
          name: string
          needs_water: boolean | null
          owner_id: string
          power_required_kw: number | null
          price_per_pax: number | null
          rating_avg: number | null
          rating_count: number | null
          service_radius_km: number | null
          setup_minutes: number | null
          slug: string
          status: Database["public"]["Enums"]["airfnb_truck_status"] | null
          tagline: string | null
          updated_at: string | null
        }
        Insert: {
          base_city?: string | null
          base_price?: number | null
          capacity?: number | null
          created_at?: string | null
          description?: string | null
          dimensions_m?: number[] | null
          featured?: boolean | null
          homologation_expires_at?: string | null
          id?: string
          insurance_expires_at?: string | null
          max_event_pax?: number | null
          min_event_pax?: number | null
          name: string
          needs_water?: boolean | null
          owner_id: string
          power_required_kw?: number | null
          price_per_pax?: number | null
          rating_avg?: number | null
          rating_count?: number | null
          service_radius_km?: number | null
          setup_minutes?: number | null
          slug: string
          status?: Database["public"]["Enums"]["airfnb_truck_status"] | null
          tagline?: string | null
          updated_at?: string | null
        }
        Update: {
          base_city?: string | null
          base_price?: number | null
          capacity?: number | null
          created_at?: string | null
          description?: string | null
          dimensions_m?: number[] | null
          featured?: boolean | null
          homologation_expires_at?: string | null
          id?: string
          insurance_expires_at?: string | null
          max_event_pax?: number | null
          min_event_pax?: number | null
          name?: string
          needs_water?: boolean | null
          owner_id?: string
          power_required_kw?: number | null
          price_per_pax?: number | null
          rating_avg?: number | null
          rating_count?: number | null
          service_radius_km?: number | null
          setup_minutes?: number | null
          slug?: string
          status?: Database["public"]["Enums"]["airfnb_truck_status"] | null
          tagline?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_trucks_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    };
    Views: {
      airfnb_v_booking_full: {
        Row: {
          currency: string | null
          ends_at: string | null
          event_id: string | null
          event_kind: Database["public"]["Enums"]["airfnb_event_kind"] | null
          event_title: string | null
          id: string | null
          organizer_id: string | null
          pax_count: number | null
          starts_at: string | null
          status: Database["public"]["Enums"]["airfnb_booking_status"] | null
          total_amount: number | null
          trucks: Json[] | null
        }
        Relationships: [
          {
            foreignKeyName: "airfnb_bookings_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "airfnb_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      airfnb_v_truck_card: {
        Row: {
          base_city: string | null
          base_price: number | null
          capacity: number | null
          category_slugs: string[] | null
          cover_url: string | null
          featured: boolean | null
          id: string | null
          name: string | null
          rating_avg: number | null
          rating_count: number | null
          slug: string | null
          status: Database["public"]["Enums"]["airfnb_truck_status"] | null
          tagline: string | null
        }
        Insert: {
          base_city?: string | null
          base_price?: number | null
          capacity?: number | null
          category_slugs?: never
          cover_url?: never
          featured?: boolean | null
          id?: string | null
          name?: string | null
          rating_avg?: number | null
          rating_count?: number | null
          slug?: string | null
          status?: Database["public"]["Enums"]["airfnb_truck_status"] | null
          tagline?: string | null
        }
        Update: {
          base_city?: string | null
          base_price?: number | null
          capacity?: number | null
          category_slugs?: never
          cover_url?: never
          featured?: boolean | null
          id?: string | null
          name?: string | null
          rating_avg?: number | null
          rating_count?: number | null
          slug?: string | null
          status?: Database["public"]["Enums"]["airfnb_truck_status"] | null
          tagline?: string | null
        }
        Relationships: []
      }

      /* ------- Marketplace tables (migrations 09-12) ------- */

      airfnb_event_requests: {
        Row: AirfnbEventRequestRow;
        Insert: Partial<AirfnbEventRequestRow> & {
          organizer_id: string; title: string; start_at: string; expected_pax: number;
        };
        Update: Partial<AirfnbEventRequestRow>;
        Relationships: [];
      };

      airfnb_applications: {
        Row: AirfnbApplicationRow;
        Insert: Partial<AirfnbApplicationRow> & {
          request_id: string; truck_id: string; proposed_price: number;
        };
        Update: Partial<AirfnbApplicationRow>;
        Relationships: [];
      };

      airfnb_lock_fees: {
        Row: AirfnbLockFeeRow;
        Insert: Partial<AirfnbLockFeeRow> & {
          application_id: string; amount: number; due_until: string;
        };
        Update: Partial<AirfnbLockFeeRow>;
        Relationships: [];
      };

      airfnb_request_invitations: {
        Row: AirfnbRequestInvitationRow;
        Insert: Partial<AirfnbRequestInvitationRow> & { request_id: string; truck_id: string };
        Update: Partial<AirfnbRequestInvitationRow>;
        Relationships: [];
      };

      airfnb_truck_alert_prefs: {
        Row: AirfnbTruckAlertPrefRow;
        Insert: Partial<AirfnbTruckAlertPrefRow> & { truck_id: string };
        Update: Partial<AirfnbTruckAlertPrefRow>;
        Relationships: [];
      };
    };
    Functions: {
      airfnb_is_admin: { Args: never; Returns: boolean };
      airfnb_truck_is_available: {
        Args: { p_from: string; p_to: string; p_truck: string };
        Returns: boolean;
      };
      airfnb_calculate_lock_fee: {
        Args: { p_application: string };
        Returns: { platform_fee: number; organizer_share: number; total: number };
      };
      airfnb_match_score: {
        Args: { p_truck: string; p_request: string };
        Returns: number;
      };
      airfnb_recommend_slots: {
        Args: { p_kind: AirfnbDatabase["public"]["Enums"]["airfnb_event_kind"]; p_pax: number };
        Returns: number;
      };
      airfnb_find_matching_requests: {
        Args: { p_truck: string; p_limit?: number };
        Returns: Array<{
          request_id: string;
          title: string;
          city: string | null;
          start_at: string;
          expected_pax: number;
          budget_min: number | null;
          budget_max: number | null;
          match_score: number;
        }>;
      };
      airfnb_find_matching_trucks: {
        Args: { p_request: string; p_limit?: number };
        Returns: Array<{
          truck_id: string;
          name: string;
          base_city: string | null;
          rating_avg: number;
          match_score: number;
        }>;
      };
      airfnb_recommend_trucks_for_request: {
        Args: { p_request: string; p_limit?: number };
        Returns: Array<{
          truck_id: string;
          name: string;
          base_city: string | null;
          rating_avg: number;
          match_score: number;
          already_invited: boolean;
          already_applied: boolean;
        }>;
      };
      airfnb_accept_application: {
        Args: { p_application: string };
        Returns: Json;
      };
      airfnb_shortlist_application: {
        Args: { p_application: string };
        Returns: void;
      };
      airfnb_reject_application: {
        Args: { p_application: string; p_reason?: string | null };
        Returns: void;
      };
    };
    Enums: {
      airfnb_user_role: "organizer" | "owner" | "admin" | "staff";
      airfnb_truck_status: "draft" | "pending_review" | "active" | "paused" | "archived";
      airfnb_dietary_tag:
        | "vegan" | "vegetarian" | "gluten_free" | "lactose_free"
        | "nut_free" | "halal" | "kosher" | "spicy";
      airfnb_event_kind:
        | "wedding" | "birthday" | "corporate" | "festival"
        | "conference" | "private" | "other";
      airfnb_booking_status:
        | "inquiry" | "proposal_sent" | "accepted" | "pending_lock_fee"
        | "confirmed" | "paid" | "in_progress" | "completed"
        | "cancelled" | "refunded";
      airfnb_payment_status: "pending" | "paid" | "failed" | "refunded";
      airfnb_payment_method: "stripe" | "mbway" | "multibanco" | "manual";
      airfnb_payment_direction:
        | "organizer_to_platform" | "truck_to_platform" | "platform_to_truck";
      airfnb_payment_kind: "lock_fee" | "event_payment" | "payout" | "refund";
      airfnb_service_kind:
        | "venue" | "entertainment" | "planning" | "marketing" | "rental";
      airfnb_post_status: "draft" | "scheduled" | "published" | "archived";
      airfnb_request_status:
        | "draft" | "open" | "reviewing" | "awarded"
        | "closed" | "expired" | "cancelled";
      airfnb_application_status:
        | "submitted" | "shortlisted" | "accepted" | "rejected"
        | "withdrawn" | "expired";
      airfnb_lock_fee_status: "pending" | "paid" | "expired" | "refunded" | "waived";
      airfnb_deal_type: "fixed" | "percent" | "mixed";
      airfnb_discovery_mode: "curated" | "broadcast" | "auto_match";
    };
  };
}

/**
 * Internal alias so the generator-emitted `Database["public"]["Enums"][…]`
 * references inside table types still resolve. New code should import
 * `AirfnbDatabase` directly.
 */
export type Database = AirfnbDatabase;

// Helper aliases
export type Addresses = AirfnbDatabase['public']['Tables']['airfnb_addresses']['Row'];
export type AddressesInsert = AirfnbDatabase['public']['Tables']['airfnb_addresses']['Insert'];
export type AddressesUpdate = AirfnbDatabase['public']['Tables']['airfnb_addresses']['Update'];
export type AuditLog = AirfnbDatabase['public']['Tables']['airfnb_audit_log']['Row'];
export type AuditLogInsert = AirfnbDatabase['public']['Tables']['airfnb_audit_log']['Insert'];
export type AuditLogUpdate = AirfnbDatabase['public']['Tables']['airfnb_audit_log']['Update'];
export type BlogAuthors = AirfnbDatabase['public']['Tables']['airfnb_blog_authors']['Row'];
export type BlogAuthorsInsert = AirfnbDatabase['public']['Tables']['airfnb_blog_authors']['Insert'];
export type BlogAuthorsUpdate = AirfnbDatabase['public']['Tables']['airfnb_blog_authors']['Update'];
export type BlogCategories = AirfnbDatabase['public']['Tables']['airfnb_blog_categories']['Row'];
export type BlogCategoriesInsert = AirfnbDatabase['public']['Tables']['airfnb_blog_categories']['Insert'];
export type BlogCategoriesUpdate = AirfnbDatabase['public']['Tables']['airfnb_blog_categories']['Update'];
export type BlogPosts = AirfnbDatabase['public']['Tables']['airfnb_blog_posts']['Row'];
export type BlogPostsInsert = AirfnbDatabase['public']['Tables']['airfnb_blog_posts']['Insert'];
export type BlogPostsUpdate = AirfnbDatabase['public']['Tables']['airfnb_blog_posts']['Update'];
export type BookingAddons = AirfnbDatabase['public']['Tables']['airfnb_booking_addons']['Row'];
export type BookingAddonsInsert = AirfnbDatabase['public']['Tables']['airfnb_booking_addons']['Insert'];
export type BookingAddonsUpdate = AirfnbDatabase['public']['Tables']['airfnb_booking_addons']['Update'];
export type BookingTrucks = AirfnbDatabase['public']['Tables']['airfnb_booking_trucks']['Row'];
export type BookingTrucksInsert = AirfnbDatabase['public']['Tables']['airfnb_booking_trucks']['Insert'];
export type BookingTrucksUpdate = AirfnbDatabase['public']['Tables']['airfnb_booking_trucks']['Update'];
export type Bookings = AirfnbDatabase['public']['Tables']['airfnb_bookings']['Row'];
export type BookingsInsert = AirfnbDatabase['public']['Tables']['airfnb_bookings']['Insert'];
export type BookingsUpdate = AirfnbDatabase['public']['Tables']['airfnb_bookings']['Update'];
export type Categories = AirfnbDatabase['public']['Tables']['airfnb_categories']['Row'];
export type CategoriesInsert = AirfnbDatabase['public']['Tables']['airfnb_categories']['Insert'];
export type CategoriesUpdate = AirfnbDatabase['public']['Tables']['airfnb_categories']['Update'];
export type ContactRequests = AirfnbDatabase['public']['Tables']['airfnb_contact_requests']['Row'];
export type ContactRequestsInsert = AirfnbDatabase['public']['Tables']['airfnb_contact_requests']['Insert'];
export type ContactRequestsUpdate = AirfnbDatabase['public']['Tables']['airfnb_contact_requests']['Update'];
export type ConversationParticipants = AirfnbDatabase['public']['Tables']['airfnb_conversation_participants']['Row'];
export type ConversationParticipantsInsert = AirfnbDatabase['public']['Tables']['airfnb_conversation_participants']['Insert'];
export type ConversationParticipantsUpdate = AirfnbDatabase['public']['Tables']['airfnb_conversation_participants']['Update'];
export type Conversations = AirfnbDatabase['public']['Tables']['airfnb_conversations']['Row'];
export type ConversationsInsert = AirfnbDatabase['public']['Tables']['airfnb_conversations']['Insert'];
export type ConversationsUpdate = AirfnbDatabase['public']['Tables']['airfnb_conversations']['Update'];
export type Events = AirfnbDatabase['public']['Tables']['airfnb_events']['Row'];
export type EventsInsert = AirfnbDatabase['public']['Tables']['airfnb_events']['Insert'];
export type EventsUpdate = AirfnbDatabase['public']['Tables']['airfnb_events']['Update'];
export type Faqs = AirfnbDatabase['public']['Tables']['airfnb_faqs']['Row'];
export type FaqsInsert = AirfnbDatabase['public']['Tables']['airfnb_faqs']['Insert'];
export type FaqsUpdate = AirfnbDatabase['public']['Tables']['airfnb_faqs']['Update'];
export type Favorites = AirfnbDatabase['public']['Tables']['airfnb_favorites']['Row'];
export type FavoritesInsert = AirfnbDatabase['public']['Tables']['airfnb_favorites']['Insert'];
export type FavoritesUpdate = AirfnbDatabase['public']['Tables']['airfnb_favorites']['Update'];
export type Invoices = AirfnbDatabase['public']['Tables']['airfnb_invoices']['Row'];
export type InvoicesInsert = AirfnbDatabase['public']['Tables']['airfnb_invoices']['Insert'];
export type InvoicesUpdate = AirfnbDatabase['public']['Tables']['airfnb_invoices']['Update'];
export type MenuItems = AirfnbDatabase['public']['Tables']['airfnb_menu_items']['Row'];
export type MenuItemsInsert = AirfnbDatabase['public']['Tables']['airfnb_menu_items']['Insert'];
export type MenuItemsUpdate = AirfnbDatabase['public']['Tables']['airfnb_menu_items']['Update'];
export type Messages = AirfnbDatabase['public']['Tables']['airfnb_messages']['Row'];
export type MessagesInsert = AirfnbDatabase['public']['Tables']['airfnb_messages']['Insert'];
export type MessagesUpdate = AirfnbDatabase['public']['Tables']['airfnb_messages']['Update'];
export type NewsletterSubscribers = AirfnbDatabase['public']['Tables']['airfnb_newsletter_subscribers']['Row'];
export type NewsletterSubscribersInsert = AirfnbDatabase['public']['Tables']['airfnb_newsletter_subscribers']['Insert'];
export type NewsletterSubscribersUpdate = AirfnbDatabase['public']['Tables']['airfnb_newsletter_subscribers']['Update'];
export type Notifications = AirfnbDatabase['public']['Tables']['airfnb_notifications']['Row'];
export type NotificationsInsert = AirfnbDatabase['public']['Tables']['airfnb_notifications']['Insert'];
export type NotificationsUpdate = AirfnbDatabase['public']['Tables']['airfnb_notifications']['Update'];
export type Payments = AirfnbDatabase['public']['Tables']['airfnb_payments']['Row'];
export type PaymentsInsert = AirfnbDatabase['public']['Tables']['airfnb_payments']['Insert'];
export type PaymentsUpdate = AirfnbDatabase['public']['Tables']['airfnb_payments']['Update'];
export type Profiles = AirfnbDatabase['public']['Tables']['airfnb_profiles']['Row'];
export type ProfilesInsert = AirfnbDatabase['public']['Tables']['airfnb_profiles']['Insert'];
export type ProfilesUpdate = AirfnbDatabase['public']['Tables']['airfnb_profiles']['Update'];
export type Proposals = AirfnbDatabase['public']['Tables']['airfnb_proposals']['Row'];
export type ProposalsInsert = AirfnbDatabase['public']['Tables']['airfnb_proposals']['Insert'];
export type ProposalsUpdate = AirfnbDatabase['public']['Tables']['airfnb_proposals']['Update'];
export type Reviews = AirfnbDatabase['public']['Tables']['airfnb_reviews']['Row'];
export type ReviewsInsert = AirfnbDatabase['public']['Tables']['airfnb_reviews']['Insert'];
export type ReviewsUpdate = AirfnbDatabase['public']['Tables']['airfnb_reviews']['Update'];
export type ServiceProviders = AirfnbDatabase['public']['Tables']['airfnb_service_providers']['Row'];
export type ServiceProvidersInsert = AirfnbDatabase['public']['Tables']['airfnb_service_providers']['Insert'];
export type ServiceProvidersUpdate = AirfnbDatabase['public']['Tables']['airfnb_service_providers']['Update'];
export type TruckAvailability = AirfnbDatabase['public']['Tables']['airfnb_truck_availability']['Row'];
export type TruckAvailabilityInsert = AirfnbDatabase['public']['Tables']['airfnb_truck_availability']['Insert'];
export type TruckAvailabilityUpdate = AirfnbDatabase['public']['Tables']['airfnb_truck_availability']['Update'];
export type TruckCategories = AirfnbDatabase['public']['Tables']['airfnb_truck_categories']['Row'];
export type TruckCategoriesInsert = AirfnbDatabase['public']['Tables']['airfnb_truck_categories']['Insert'];
export type TruckCategoriesUpdate = AirfnbDatabase['public']['Tables']['airfnb_truck_categories']['Update'];
export type TruckDocuments = AirfnbDatabase['public']['Tables']['airfnb_truck_documents']['Row'];
export type TruckDocumentsInsert = AirfnbDatabase['public']['Tables']['airfnb_truck_documents']['Insert'];
export type TruckDocumentsUpdate = AirfnbDatabase['public']['Tables']['airfnb_truck_documents']['Update'];
export type TruckImages = AirfnbDatabase['public']['Tables']['airfnb_truck_images']['Row'];
export type TruckImagesInsert = AirfnbDatabase['public']['Tables']['airfnb_truck_images']['Insert'];
export type TruckImagesUpdate = AirfnbDatabase['public']['Tables']['airfnb_truck_images']['Update'];
export type Trucks = AirfnbDatabase['public']['Tables']['airfnb_trucks']['Row'];
export type TrucksInsert = AirfnbDatabase['public']['Tables']['airfnb_trucks']['Insert'];
export type TrucksUpdate = AirfnbDatabase['public']['Tables']['airfnb_trucks']['Update'];
