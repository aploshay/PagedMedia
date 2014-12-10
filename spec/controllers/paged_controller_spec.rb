require 'spec_helper'
require 'json'

describe PagedsController do

  before(:all) do
    @test_paged = create(:paged, :with_pages)
    @test_paged.update_index
  end

  context '#page' do
    it 'should return pid and image ds uri given an index integer' do
      get :pages, id: @test_paged.id, index: 1
      parsed = JSON.parse response.body
      expect(parsed['id']).to eq Page.find(@test_paged.children[1]).pid
      expect(parsed['index']).to eq 1.to_s
      expect(parsed['ds_url']).to match /#{ERB::Util.url_encode(Page.find(@test_paged.children[1]).pid)}\/datastreams\/pageImage\/content$/
    end 
  end 

  after(:all) do  
    @test_paged.children.each {|page| Page.find(page).delete }
    @test_paged.reload
    @test_paged.delete
  end

end

=begin
  describe 'GET index' do
    it 'lists Pageds'
  end

  describe 'GET show' do
    it 'displays detail of a Paged'
  end

  describe 'GET new' do
    it 'displays the create form'
  end

  describe 'GET edit' do
    it 'displays the edit form'
  end

  describe 'POST create' do
    it 'stores a new Page'
  end

  describe 'PUT update' do
    it 'updates the page somehow'
  end

  describe 'DELETE destroy' do
    it 'destroys a Paged'
  end

end
=end

describe 'For page listing' do

  before(:all) do
    @test_paged = create(:paged, :with_pages)
  end

  context "when pages are listed" do  
    specify "they should be ordered according to prev and next page ids" do      
      visit pageds_path + '/' + @test_paged.pid
      page.body.index("Page 1").should < page.body.index("Page 2")
      page.body.index("Page 2").should < page.body.index("Page 3")
      page.body.index("Page 3").should < page.body.index("Page 4")
      page.body.index("Page 4").should < page.body.index("Page 5")
    end
  end
  
  context "when more than one first page is found" do
    specify "an error message should display" do
      #Find page 3 and remove prev page
      prev_sib = ''
      page3 = ''
      @test_paged.children.each {|page|
        my_page = Page.find(page)
        if my_page.logical_number == "Page 3"
          page3 = my_page
          prev_sib = my_page.prev_sib
          my_page.prev_sib = ''
          my_page.save!
        end
      }      
      visit pageds_path + '/' + @test_paged.pid
      # Return page 3's prev page
      page3.prev_sib = prev_sib
      page3.save!
      expect(page).to have_css('div.alert-error')
    end
  end

  context "when a infinite loop would occur " do
    specify "an error message should display" do
      # Find page 3 and redirect it to itself
      next_page = ''
      page3 = ''
      @test_paged.children.each {|page|
        my_page = Page.find(page)
        if my_page.logical_number == "Page 3"
          page3 = my_page
          next_page = my_page.next_sib
          my_page.next_sib = my_page.pid
          my_page.save!
        end
      }
      visit pageds_path + '/' + @test_paged.pid
      # Return page 3's prev page
      page3.next_sib = next_page
      page3.save!
      expect(page).to have_css('div.alert-error')
    end
  end
  
  context "when not all the pages are included in listing" do
    specify "an error message should display" do
      # Find page 3 and remove next page
      next_page = ''
      page3 = ''
      @test_paged.children.each {|page|
        my_page = Page.find(page)
        if my_page.logical_number == "Page 3"
          page3 = my_page
          next_page = my_page.next_sib
          my_page.next_sib = ''
          my_page.save!
        end
      }
      visit pageds_path + '/' + @test_paged.pid
      # Return page 3's prev page
      page3.next_sib = next_page
      page3.save!
      expect(page).to have_css('div.alert-error')
    end
  end
  
  after(:all) do  
    @test_paged.children.each {|page| Page.find(page).delete }
    @test_paged.reload
    @test_paged.delete
  end

it 'stores a new XML datastream'

end

describe 'For page reordering' do

  before(:all) do
    @test_paged = create(:paged, :with_pages)
  end

  context "when pages are reordered" do  
    it "should respond to reorder"
    it "should accept a list of pages that need to have their order reset" 
    it "should save the logical position of each of the pages from the list"
    it "should calculate and save previous and next siblings for each page"
  end

  after(:all) do  
    @test_paged.children.each {|page| Page.find(page).delete }
    @test_paged.reload
    @test_paged.delete
  end

end
