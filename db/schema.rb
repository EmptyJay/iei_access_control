# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_27_170405) do
  create_table "access_events", force: :cascade do |t|
    t.integer "user_id"
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "notes"
    t.index ["occurred_at"], name: "index_access_events_on_occurred_at"
    t.index ["user_id"], name: "index_access_events_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "slot", null: false
    t.integer "site_code", default: 105, null: false
    t.integer "card_number", null: false
    t.boolean "active", default: true, null: false
    t.boolean "synced", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "tier", default: "standard", null: false
    t.integer "write_counter"
    t.index ["card_number"], name: "index_users_on_card_number", unique: true
    t.index ["slot"], name: "index_users_on_slot", unique: true
    t.index ["tier"], name: "index_users_on_tier"
    t.index ["write_counter"], name: "index_users_on_write_counter"
  end

  add_foreign_key "access_events", "users"
end
