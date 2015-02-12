# Despite its name, this is a functional test of pageds_controller *and its supporting cast*.
describe 'For page listing' do
  let!(:test_paged) { FactoryGirl.create :paged, :with_pages }
  let(:page3) { test_paged.pages.sort { |a, b| a.logical_number <=> b.logical_number }[2] } 

  context "when pages are listed" do  
    specify "they should be ordered according to prev and next page ids" do
      visit pageds_path + '/' + test_paged.pid
      page.body.index("Page 1").should be < page.body.index("Page 2")
      page.body.index("Page 2").should be < page.body.index("Page 3")
      page.body.index("Page 3").should be < page.body.index("Page 4")
      page.body.index("Page 4").should be < page.body.index("Page 5")
    end
  end
  
  context "when more than one first page is found" do
    before(:each) do
      # Remove page 3's prev_page
      page3.prev_page = ''
      page3.skip_sibling_validation = true
      page3.save!(unchecked: true)
    end
    specify "an error message should display" do
      visit pageds_path + '/' + test_paged.pid + '/validate'
      expect(page).to have_css('div.alert-error')
    end
  end

  context "when an infinite loop would occur " do
    before(:each) do
      # Point page 3's next_page to itself
      page3.next_page = page3.pid
      page3.skip_sibling_validation = true
      page3.save!(unchecked: true)
    end
    specify "an error message should display" do
      visit pageds_path + '/' + test_paged.pid + '/validate'
      expect(page).to have_css('div.alert-error')
    end
  end
  
  context "when not all the pages are included in listing" do
    before(:each) do
      # Point page 3's next_page to nothing
      page3.next_page = ''
      page3.skip_sibling_validation = true
      page3.save!(unchecked: true)
    end
    specify "an error message should display" do
      visit pageds_path + '/' + test_paged.pid + '/validate'
      expect(page).to have_css('div.alert-error')
    end
  end

it 'stores a new XML datastream'

end
=begin
# Abortive attempt at testing the drag/drop page reordering interface.  This
# turns out to be really hard to do, because of JQuery weirdness.  After
# discussion, I think we agreed that this is better done as a controller
# test of some kind.
#
# This depends on https://github.com/mattheworiordan/jquery.simulate.drag-sortable.js
#
# I could not find a way to fetch the script from the application assets, so I
# just dropped it into my local webserver.  The author thinks serving it from
# the application is possible but gives no example.

feature 'User reorders pages', js: true do

  let!(:test_paged) { FactoryGirl.create(:paged, :with_pages) }

  scenario 'by dragging and dropping in the page order list' do
    visit pageds_path + '/' + test_paged.pid
    sortablePages = page.all(:xpath, "//ul[@id='sortable_pages']/li")
    puts 'sortablePages:'
    for i in 0..sortablePages.length-1 do p sortablePages[i] end
    puts 'test_paged.pages:'
    for i in 0..test_paged.pages.length-1 do p test_paged.pages[i] end
    # find a likely page, drag it across another and drop it.
    #sortablePages[1].drag_to(sortablePages[0]) # doesn't work!
    puts 'sortablePages[0]:  ', sortablePages[0].native.id
    url = '"https://mhw.ulib.iupui.edu/~mwood/jquery.simulate.drag-sortable.js"' # FIXME don't depend on Mark's webserver
    function = "function() {$(\"li##{sortablePages[0][:id]}\").simulateDragSortable({ move: 1});}"
    script = "$.getScript(#{url}, #{function});"
    p script
    page.execute_script script
    test_paged.save

    test_paged.reload
    # check the page order list
    visit pageds_path + '/' + test_paged.pid
    sortablePages = page.all(:xpath, "//ul[@id='sortable_pages']/li")
    puts 'sortablePages:'
    for i in 0..sortablePages.length-1 do p sortablePages[i] end
    puts 'test_paged.pages:'
    for i in 0..test_paged.pages.length-1 do p test_paged.pages[i] end
  end

  scenario "accepts a list of pages that need to have their order reset"
  scenario "saves the logical position of each of the pages from the list"
  scenario "calculates and saves previous and next siblings for each page"

end
=end
