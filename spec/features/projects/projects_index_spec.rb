#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

require 'spec_helper'
require 'features/projects/projects_page'


describe 'Projects index page', type: :feature, js: true, with_settings: { login_required?: false } do
  let!(:admin) { FactoryGirl.create :admin, firstname: 'Admin', lastname: 'Larmin', login: 'admin' }

  let!(:manager)   { FactoryGirl.create :role, name: 'Manager' }
  let!(:developer) { FactoryGirl.create :role, name: 'Developer' }

  let!(:custom_field) { FactoryGirl.create :project_custom_field }

  let!(:project) { FactoryGirl.create(:project, name: 'Plain project', identifier: 'plain-project') }
  let!(:public_project) do
    FactoryGirl.create(:project,
                       name: 'Public project',
                       identifier: 'public-project',
                       is_public: true)
  end
  let!(:development_project) do
    FactoryGirl.create(:project,
                       name: 'Development project',
                       identifier: 'development-project')
  end

  def visit_list_and_open_filter_form_as(user)
    login_as(user)
    visit projects_path
    click_button('Show/hide filters')
  end

  def set_filter(name, human_name, human_operator = nil, values = [])
    select human_name, from: 'add_filter_select'
    within('li[filter-name="' + name + '"]') do
      select human_operator, from: 'operator'
      if values.any?
        case name
        when 'name_and_identifier'
          fill_in 'value', with: values.first
        end
      end
    end
  end

  feature 'restricts project visibility' do
    feature 'for a anonymous user' do
      scenario 'only public projects shall be visible' do
        visit projects_path

        expect(page).to_not have_text(project.name)
        expect(page).to have_text(public_project.name)
      end
    end

    # TODO: Fix permission check so that this feature spec passes.
    #
    # feature 'for project members' do
    #   let!(:user) do
    #     FactoryGirl.create(:user,
    #                        member_in_project: development_project,
    #                        member_through_role: developer,
    #                        login: 'nerd',
    #                        firstname: 'Alan',
    #                        lastname: 'Turing')
    #   end
    #
    #   scenario 'only public project or those the user is member of shall be visible' do
    #     login_as(user)
    #     visit projects_path
    #     expect(page).to have_text(development_project.name)
    #     expect(page).to have_text(public_project.name)
    #     expect(page).to_not have_text(project.name)
    #   end
    #   pending "Not 'visible' CFs shall only be visible for admins"
    # end

    feature 'for admins' do
      scenario 'test that all projects are visible' do
        login_as(admin)
        visit projects_path

        expect(page).to have_text(public_project.name)
        expect(page).to have_text(project.name)
      end
      pending "test that not 'visible' CFs are visible"
    end
  end

  feature 'without valid Enterprise token' do
    scenario 'CF columns and filters are not visible' do
      visit_list_and_open_filter_form_as admin

      # CF's columns are not present:
      expect(page).to_not have_text(custom_field.name.upcase)
      # CF's filters are not present:
      expect(page).to_not have_select('add_filter_select', with_options: [custom_field.name])
    end
  end

  feature 'with valid Enterprise token' do
    before do
      allow(EnterpriseToken).to receive(:allows_to?).with(:custom_fields_in_projects_list).and_return(true)
      allow(EnterpriseToken).to receive(:allows_to?).with(:define_custom_style).and_return(true)
    end

    scenario 'CF columns and filters are visible' do
      visit_list_and_open_filter_form_as admin

      # CF's column is present:
      expect(page).to have_text(custom_field.name.upcase)
      # CF's filter is present:
      expect(page).to have_select('add_filter_select', with_options: [custom_field.name])
    end
  end

  feature 'with a filter set' do
    scenario 'it should only show the matching projects and filters' do
      visit_list_and_open_filter_form_as admin

      set_filter('name_and_identifier',
                 'Name or identifier',
                 'contains',
                 ['Plain'])

      click_on 'Filter'
      # Filter is applied: Only the project that contains the the word "Plain" gets listed
      expect(page).to_not have_text(public_project.name)
      expect(page).to have_text(project.name)
      # Filter form is visible and the filter is still set.
      expect(page).to have_css('li[filter-name="name_and_identifier"]')
    end
  end

  feature 'when paginating' do
    before do
      allow(Setting).to receive(:per_page_options_array).and_return([1])
    end

    scenario 'it keeps applying filters and order' do
      visit_list_and_open_filter_form_as admin

      set_filter('name_and_identifier',
                 'Name or identifier',
                 'doesn\'t contain',
                 ['Plain'])

      click_on 'Filter'

      # Sorts ASC by name
      click_on 'Sort by "Project"'

      # Results should be filtered and ordered ASC by name
      expect(page).to have_text(development_project.name)
      expect(page).to_not have_text(project.name)        # as it filtered away
      expect(page).to have_text('Next')          # as the result set is larger than 1
      expect(page).to_not have_text(public_project.name) # as it is on the second page

      click_on '2' # Go to pagination page 2

      # On page 2 you should see the second page of the filtered set ordered ASC by name
      expect(page).to have_text(public_project.name)
      expect(page).to_not have_text(project.name)             # Filtered away
      expect(page).to_not have_text('Next')                   # Filters kept active, so there is no third page.
      expect(page).to_not have_text(development_project.name) # That one should be on page 1

      # Sorts DESC by name
      click_on 'Ascending sorted by "Project"'

      # On page 2 the same filters should still be intact but the order should be DESC on name
      expect(page).to have_text(development_project.name)
      expect(page).to_not have_text(project.name)        # Filtered away
      expect(page).to_not have_text('Next')              # Filters kept active, so there is no third page.
      expect(page).to_not have_text(public_project.name) # That one should be on page 1

      # Sending the filter form again what implies to compose the request freshly
      click_on 'Filter'

      # We should see page 1, resetting pagination, as it is a new filter, but keeping the DESC order on the project
      # name
      expect(page).to have_text(public_project.name)
      expect(page).to_not have_text(development_project.name) # as it is on the second page
      expect(page).to_not have_text(project.name)             # as it filtered away
      expect(page).to have_text('Next')               # as the result set is larger than 1
    end
  end

  feature 'when filter of type' do
    feature 'Name and identifier' do
      scenario 'gives results in both, name and identifier' do
        visit_list_and_open_filter_form_as admin

        # Filter on model attribute 'name'
        set_filter('name_and_identifier',
                   'Name or identifier',
                   'doesn\'t contain',
                   ['Plain'])

        click_on 'Filter'

        expect(page).to have_text(development_project.name)
        expect(page).to have_text(public_project.name)
        expect(page).to_not have_text(project.name)

        # Filter on model attribute 'identifier'
        page.find('li[filter-name="name_and_identifier"] .filter_rem').click

        set_filter('name_and_identifier',
                   'Name or identifier',
                   'is',
                   ['plain-project'])

        click_on 'Filter'

        expect(page).to have_text(project.name)
        expect(page).to_not have_text(development_project.name)
        expect(page).to_not have_text(public_project.name)
      end
    end

    # scenario 'Active or archived' do
    #   visit_list_and_open_filter_form_as admin
    #
    #   # value selection defaults to "active"'
    #
    #   # Filter has three operators 'all', 'active' and 'archived'
    # end

    feature "Created on" do
      feature "selecting operator" do
        feature "'today'" do
          pending "show projects that were created today"
        end

        feature "'this week'" do
          pending "show projects that were created this week"
        end

        feature "'on'" do
          pending "filters on a specific date"
        end

        feature "'less than or equal' days ago" do
          pending "only shows matching projects"
        end

        feature "'more than or equal' days ago" do
          pending "only shows matching projects"
        end

        feature "between two dates" do
          pending "only shows matching projects"
          pending "selecting same date for from and to value shows projects of that date"
        end

      end
    end

    feature "Latest activity at" do
      pending "filter uses correct data"
    end

    feature "CF List" do
      pending "switching to multiselect keeps the current selection"
      pending "switching to single select keeps the first selection"
      pending "whith only one value selected next load shows single select"
      pending "whith more than one value selected next load shows multi select"
    end

    feature "CF date" do
      pending "shows correct results"
    end
  end
  # TODO: Rewrite old Cucumber test for archiving to RSpec.
end