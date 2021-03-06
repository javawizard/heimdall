# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  badge_number           :string
#  confirmation_sent_at   :datetime
#  confirmation_token     :string
#  confirmed_at           :datetime
#  current_sign_in_at     :datetime
#  current_sign_in_ip     :string
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  failed_attempts        :integer          default(0), not null
#  last_sign_in_at        :datetime
#  last_sign_in_ip        :string
#  locked_at              :datetime
#  name                   :string
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  sign_in_count          :integer          default(0), not null
#  super_user             :boolean          default(FALSE), not null
#  unconfirmed_email      :string
#  unlock_token           :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  household_id           :bigint           not null
#
# Indexes
#
#  index_users_on_confirmation_token    (confirmation_token) UNIQUE
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_household_id          (household_id)
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (household_id => households.id)
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :timeoutable,, :registerable, and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable, :lockable

  has_paper_trail skip: [:password, :password_confirmation, :encrypted_password]

  belongs_to :household

  has_many :certification_issuances
  has_many :certification_instructors

  has_many :received_certifications, through: :certification_issuances, source: :certification
  has_many :instructed_certifications, through: :certification_instructors, source: :certification

  has_many :certified_certification_issuances, class_name: 'CertificationIssuance', foreign_key: 'certifier_id', inverse_of: :certifier

  has_many :badge_reader_manual_users
  has_many :badge_reader_scans

  has_many :manual_user_badge_readers, through: :badge_reader_manual_users, source: :badge_reader

  ransacker :has_multiple_household_members, formatter: ActiveModel::Type::Boolean.new.method(:cast) do
    Arel.sql('exists(select id from users as household_users where household_users.household_id = users.household_id and household_users.id != users.id)')
  end

  def display_name
    name
  end

  # Household logic. This can probably be simplified, but the gist of what it
  # needs to do is: households should function as anonymous groups of users.
  # Every user belongs to exactly one household and every household has one or
  # more users.

  def household_user_ids
    @household_user_ids || household.users.where.not(id: id).pluck(:id)
  end

  def household_user_ids=(ids)
    # cleanup; activeadmin addons's selected_list field type passes ids as
    # strings and passes a blank one as the first argument (which looks like
    # its attempt to ensure a parameter for this association is always passed
    # so as to trigger the removal of all of its values if it's been blanked
    # out in the form, but it doesn't bother removing it if there are in fact
    # items in the association)
    ids = ids.select(&:presence).compact.map { |id| Integer(id) }
    @household_user_ids = ids
  end

  def household_users
    User.where(id: household_user_ids)
  end

  # Give each user their own household when they're created
  after_initialize do
    self.household = Household.new if new_record?
  end

  # Destroy our household when we're destroyed if we're the last user in it
  after_destroy do
    household.destroy! if household.users.blank?
  end

  after_save do
    # This is complicated enough that I'm seriously considering writing this
    # project's first tests for it...
    current_household_members = household.users.where.not(id: id).pluck(:id)
    old_household_members = current_household_members - household_user_ids
    new_household_members = household_user_ids - current_household_members

    old_household_members.each do |id|
      # Detach them from our household by putting them into a newly created
      # household
      user = User.find(id)
      user.update!(household: Household.new)
    end

    new_household_members.each do |id|
      # Attach them to our household by first setting our household as theirs...
      user = User.find(id)
      old_household = user.household
      user.update!(household: self.household)

      # ...and then destroying their former household if it no longer has any
      # users.
      old_household.destroy! if old_household.users.blank?
    end

    @household_user_ids = nil
  end
end
