#
# Ruby process for batch ingest, called by import_batches rake task
#

def ingest_folders
  ingest_root = "spec/fixtures/ingest/pmp/"
  return Dir.glob(ingest_root + "*").select { |f| File.directory?(f) }
end

#FIXME: get actual id, date values
def manifest_hash(id: "mybatch", date: "12-1-2014")
  { 'manifest' => { 'id' => id, 'date' => date },
    'pageds' => []
  }
end

#FIXME: decide on .to_s calls
def paged_hash(options = {}) 
  { 'descMetadata' => { 'title' => options['title'],
                        'creator' => options['creator'],
			'type' => options['type'],
			'publisher' => options['publisher'],
			'publisher_place' => options['publisher_place'],
			'paged_struct' => options['paged_struct'] || []
                      },
    'content' => { 'pagedXML' => options['pagedXML']},
    'pages' => options['pages'] || []
  }
end

#FIXME: add pageOCR, pageXML
def page_hash(options = {})
  { 'descMetadata' => { 'logical_number' => options['logical_number'],
                        'text' => options['text'],
			'page_struct' => options['page_struct'] || []
                      },
    'content' => { 'pageImage' => options['pageImage'],
                   'pageOCR' => options['pageOCR'],
		   'pageXML' => options['pageXML']
                 }
  }
end

def structure_array(struct_string, delimiter = '--')
  result = struct_string.split(delimiter)
  result.each_with_index do |value, index|
    result[index] = result[index - 1] + delimiter + value unless index == 0
  end
  result
end

def process_batches
  ingest_folders.each_with_index do |subdir, index|
    puts "Processing batch directory #{index + 1} of #{ingest_folders.size}: #{subdir}"
    xlsx_files = Dir.glob(subdir + "/" + "manifest*.xlsx").select { |f| File.file?(f) }
    if xlsx_files.any?
      xlsx_files.each do |manifest_filename|
        begin
          manifest = Roo::Excelx.new(manifest_filename)
        rescue
          puts "ABORTING: Unable to open/parse manifest file: #{manifest_filename}"
          manifest = nil
        end
        convert_manifest(subdir, manifest) unless manifest.nil?
      end
    else
      puts "No package files found to process."
    end
  end
end

def convert_manifest(subdir, manifest)
  # validate paged, abort otherwise
  # validate page, abort otherwise
  begin
    paged_sheet = manifest.sheet('Paged')
  rescue
    puts "ABORTING: Paged sheet not found."
  end
  if paged_sheet
    begin
      page_sheet = manifest.sheet('Page')
    rescue
      puts "ABORTING: Page sheet not found."
      #FIXME: abort
    end
    manifest.default_sheet = 'Paged'
    #FIXME: assign actual id, date values
    manifest_yaml = manifest_hash
    2.upto(paged_sheet.last_row).each do |n|
      hashed_row = Hash[(paged_sheet.row(1).zip(paged_sheet.row(n)))]
      hashed_row['paged_struct'] = structure_array(hashed_row['is_part_of'])
      hashed_row.delete('is_part_of')
      puts "Parsing paged object: #{hashed_row['title']}"
      #for each batch id: parse page, pages data
      manifest_yaml['pageds'] << paged_hash(hashed_row)
      #ADD: paged_struct
      #PROCESS PAGES
      manifest.default_sheet = 'Page'
      print "Parsing pages:"
      2.upto(page_sheet.last_row).each do |page|
        hashed_page = Hash[(page_sheet.row(1).zip(page_sheet.row(page)))]
        hashed_page['page_struct'] = structure_array(hashed_page['is_part_of'])
	hashed_page.delete('is_part_of')
        if hashed_page['batch_id'] == hashed_row['batch_id']
          manifest_yaml['pageds'][-1]['pages'] << page_hash(hashed_page) if hashed_page['batch_id'] == hashed_row['batch_id']
	  print "."
	end
      end
      print "\n#{manifest_yaml['pageds'][-1]['pages'].size} pages parsed.\n"
      manifest.default_sheet = 'Paged'
    end
    begin
      filename = subdir + "/" + "manifest.yml"
      File.open(filename, 'w') {|f| f.write manifest_yaml.to_yaml }
    rescue
      puts "ABORT: Problem saving manifest YAML file."
    end
  end
end

def ingest_batches
  ingest_folders.each_with_index do |subdir, index|
    puts "Ingesting batch directory #{index + 1} of #{ingest_folders.size}: #{subdir}"
    manifest_files = Dir.glob(subdir + "/" + "manifest*.yml").select { |f| File.file?(f) }
    if manifest_files.any?
      manifest_files.each do |manifest_filename|
        begin
          manifest = YAML.load_file(manifest_filename)
        rescue
          puts "ABORTING: Unable to open/parse manifest file: #{manifest_filename}."
          manifest = nil
        end
	puts "Found manifest file: #{manifest_filename}"
        import_manifest(subdir, manifest) unless manifest.nil?
      end
    else
      puts "No manifest YAML files found in this directory."
    end
  end
end

def import_manifest(subdir, manifest)
  if manifest["pageds"].nil? or manifest["pageds"].empty?
    puts "ABORTING: No paged documents listed in manifest."
  else
    manifest["pageds"].each do |paged|
      import_paged(subdir, paged)
    end
  end
end

def import_paged(subdir, paged_yaml)
  paged_attributes = {}
  begin
    paged_yaml["descMetadata"].each_pair do |key, value|
      paged_attributes[key.to_sym] = value
    end
  rescue
    puts "ABORTING PAGED CREATION: invalid structure in descMetadata"
    return
  end
  if paged_attributes.any?
    begin
      paged = Paged.new(paged_attributes)
    rescue
      puts "ABORTING PAGED CREATION: invalid contents of descMetadata:"
      puts paged_attributes.inspect
      return
    end
  end
  if paged_yaml["content"] && paged_yaml["content"]["pagedXML"]
    begin
      xmlPath = Rails.root + subdir + "content/" + paged_yaml["content"]["pagedXML"]
      puts "Adding pagedXML file."
      paged.pagedXML.content = File.open(xmlPath)
    rescue
      puts "ABORTING PAGED CREATION: unable to open specified XML file: #{xmlPath}"
      return
    end
  else
    puts "No pagedXML file specified."
  end
  if paged
    #TODO: check for failed connection
    if paged.save
      puts "Paged object #{paged.pid} successfully created."
    else
      puts "ABORTING PAGED CREATION: problem saving paged object"
      puts paged.errors.messages
      return
    end

    pages_yaml = paged_yaml["pages"]
    if pages_yaml.nil? or pages_yaml.empty?
      puts "No pages specified for page object."
    else
      #TODO: check page count exists?
      page_count = pages_yaml.count
      puts "Processing #{page_count.to_s} pages."
      #TODO: check page count matches pages provided?
      pages = []
      prev_page = nil
      print "Creating page records:"
      (0...page_count).each do |index|
        page_attributes = { paged_id: paged.pid, skip_sibling_validation: true }
        page_attributes[:prev_page] = prev_page.pid if prev_page
        pages_yaml[index]["descMetadata"].each_pair do |key, value|
          page_attributes[key.to_sym] = value
        end
        begin
	  page = Page.new(page_attributes)
        rescue
          puts "ABORTING: invalid page attributes:"
          puts page_attributes.inspect
          break
        end
	#FIXME: add begin/rescue blocks for opening files
        if pages_yaml[index]["content"]
          pageImage = pages_yaml[index]["content"]["pageImage"]
	  page.pageImage.content = File.open(Rails.root + subdir + "content/" + pageImage) if pageImage

          # FIXME: this is failing
          # pageOCR = pages_yaml[index]["content"]["pageOCR"]
	  # page.pageOCR.content = File.open(Rails.root + subdir + "content/" + pageOCR) if pageOCR

          pageXML = pages_yaml[index]["content"]["pageXML"]
	  page.pageXML.content = File.open(Rails.root + subdir + "content/" + pageXML) if pageXML
	end
	if page.save(unchecked: true)
	  page.reload
	  pages << page
          unless prev_page.nil?
            prev_page.next_page = page.pid
            unless prev_page.save(unchecked: true)
              puts "ABORT: problems re-saving prior page"
              puts prev_page.errors.messages
              pages = []
              break
            end
          end
          prev_page = page
	  print "."
	else
	  puts "ABORT: problems saving page"
	  puts page.errors.messages
	  #TODO: destroy pages, paged?
	  pages = []
	  break
	end
      end
      puts "\nUpdating paged index."
      paged.reload
      paged.update_index
      puts "Done.\n"
    end
  end
end
