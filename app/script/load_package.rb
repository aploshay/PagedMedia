require File.join('.', 'spec', 'spec_helper.rb')

describe 'Loading objects' do

  before(:all) do
    @test_paged = create(:paged, :package, :package_with_pages)
    @test_paged.update_index
  end

  context 'Loading an example score' do
    it 'should create a score and load pages' do
      @test_paged.children.each {|page|
        my_page = Page.find(page)
        p 'Loaded ' + my_page.logical_number
      }
    end
  end 
end
