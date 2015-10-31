class JavaSecurityCrawler < CommonSecurity


  A_GIT_DB = "https://github.com/victims/victims-cve-db.git"


  def self.logger
    ActiveSupport::Logger.new('log/java_security.log')
  end


  def self.crawl
    db_dir = '/tmp/victims-cve-db'
    java_dir = '/tmp/victims-cve-db/database/java/'

    `(cd /tmp && git clone #{A_GIT_DB})`
    `(cd #{db_dir} && git pull)`

    i = 0
    logger.info "start reading yaml files"
    all_yaml_files( java_dir ) do |filepath|
      i += 1
      logger.info "##{i} parse yaml: #{filepath}"
      parse_yaml filepath
    end
  end


  def self.all_yaml_files(dir, &block)
    Dir.glob "#{dir}/**/*.yaml" do |filepath|
      block.call filepath
    end
  rescue => e
    logger.error e.message
    logger.error e.backtrace.join("\n")
  end


  def self.parse_yaml filepath
    yml = Psych.load_file( filepath )
    yml['affected'].to_a.each do |affected|
      groupId    = affected['groupId']
      artifactId = affected['artifactId']
      prod_key   = "#{groupId}/#{artifactId}".downcase

      sv = fetch_sv Product::A_LANGUAGE_JAVA, prod_key, yml["cve"]
      update( sv, yml, affected )
      mark_affected_versions( sv, affected['version'] )
      sv.save
    end
  rescue => e
    self.logger.error "ERROR in crawl_yml Message: #{e.message}"
    self.logger.error e.backtrace.join("\n")
  end


  def self.update sv, yml, affected
    sv.description = yml['description']
    sv.summary     = yml['title']
    sv.cve         = yml['cve']
    sv.cvss_v2     = yml['cvss_v2']
    sv.affected_versions_string = affected['version'].to_a.join(" && ")
    sv.patched_versions_string  = affected['fixedin'].to_a.join(" && ")
    yml["references"].to_a.each do |reference|
      sv.links[reference] = reference if !sv.links.include?(reference)
    end
  end


  def self.mark_affected_versions sv, affected
    product = sv.product
    return nil if product.nil?

    affected_versions = []
    affected.each do |version_expr|
      if version_expr.match(/,/)
        sps    = version_expr.split(",")
        start  = sps[1]
        start  = "#{start}." if start.match(/-\z/).nil?
        subset = VersionService.versions_start_with( product.versions, start )
        affected_versions += VersionService.from_ranges( subset, version_expr )
        next
      end
      affected_versions += VersionService.from_ranges( product.versions, version_expr )
    end

    mark_versions( sv, product, affected_versions )
  end


end