# A mixin providing navigational behavior in a tree of containers.  Sibling
# Nodes maintain local order through the prev_sib and next_sib references, which
# contain PIDs of Nodes.  A child Node remembers its parent by PID as its
# 'parent' attribute.  A parent Node has an array of its childrens' PIDs in the
# 'children' attribute.
#
# A Node may have no children (if it is a leaf node, such as a Page) or no
# parent (if it is at the top of the tree).
#--
# Copyright 2014 Indiana University

module Node# < ActiveFedora::Base

  def self.included(including_class)
    including_class.class_eval do
      include Hydra::AccessControls::Permissions

      has_metadata 'nodeMetadata', type: NodeMetadata, label: 'PMP generic node metadata'

      # PID of my sibling immediately "before" me
      has_attributes :prev_sib, datastream: 'nodeMetadata', multiple: false
      # PID of my sibling which is immediately "after" me
      has_attributes :next_sib, datastream: 'nodeMetadata', multiple: false
      # PID of my parent node, if any
      has_attributes :parent, datastream: 'nodeMetadata', multiple: false
      # PIDs of my child Nodes
      has_attributes :children, datastream: 'nodeMetadata', multiple: true

      # skip_sibling_validation both skips the custom validation and runs an unchecked save
      attr_accessor :skip_sibling_validation
      validate :validate_has_required_siblings, unless: :skip_sibling_validation
    end
  end

  # A link is "unset" if it is nil or an empty String
  def unset?(attribute)
    attribute.nil? || attribute.empty?
  end

  # If the parent is empty, sibling pointers should be nil, otherwise at least
  # one must be non-nil.
  def validate_has_required_siblings
    return if parent.nil?
    my_parent = self.class.find(parent)

    # Parent has no children yet, so this node can't have siblings
    if (my_parent.children.size == 0)
      errors.add(:prev_sib, 'prev_sib must be empty') if !unset?(prev_sib)
      errors.add(:next_sib, 'next_sib must be empty') if !unset?(next_sib)
      return
    end

    # At least one child of my parent already exists.  Must have at least one
    # sibling unless the one child is this one (we are updating, not creating).
    if (unset?(prev_sib) && unset?(next_sib) &&
        ((my_parent.children.size > 1) || (self.class.find(my_parent.children.first).pid != pid)))
      errors[:base] << 'must have one or both siblings if parent has children'
    end
  end


  # Link this node into the "family tree".
  # These saves should be in a transaction, but does Fedora do transactions?
  #
  # The general plan is to:
  #
  # 1. sanity-check all "family" relationships;
  # 2. persist this object;
  # 3. update this object's relatives with relationships to this object.
  #
  # In that way, this object should be available to its relatives in its new
  # state for *their* sanity-checking as they persist themselves after update.
  # Any new relationships should already be sane before persisting, so there
  # should be no need to undo this object's state change due to problems with
  # relatives.
  #
  # '<tt>foo.save(unchecked: 1)</tt>' bypasses integrity checks.  Don't!  It's for this
  # method's internal use.
  def save(opts={})

    if (opts.has_key?(:unchecked))
      return super()
    end

    # Get a copy of my supposed parent.
    my_parent = self.class.find(parent) unless parent.nil?

    # Check that prev_sib is a child of my parent.
    unless (unset?(prev_sib))
      if (parent.nil?)
        logger.error("#{self.class.name} #{pid}:  unowned node cannot have siblings")
        errors.add(:prev_sib, 'Unowned node cannot have siblings')
        return false
      else
        unless (my_parent.children.include?(prev_sib))
          logger.error("#{self.class.name} #{pid}:  #{prev_sib} not a child of #{my_parent.pid}")
          errors.add(:prev_sib, "#{prev_sib} not a child of #{my_parent.pid}")
          return false
        end
      end

      prev_sibling = self.class.find(prev_sib)
      if (prev_sibling.next_sib != next_sib) && (prev_sibling.next_sib != pid)
        logger.error("#{self.class.name} #{pid}:  invalid next_sib #{next_sib}")
        errors.add(:next_sib, "invalid next_sib #{next_sib}")
        return false
      end
    end

    # Check that next_sib is a child of my parent.
    unless (unset?(next_sib))
      if (parent.nil?)
        logger.error("#{self.class.name} #{pid}:  unowned node cannot have siblings")
        errors.add(:next_sib, 'Unowned node cannot have siblings')
        return false
      else
        unless (my_parent.children.include?(next_sib))
          logger.error("#{self.class.name} #{pid}:  #{next_sib} not a child of #{my_parent.pid}")
          errors.add(:next_sib, "#{next_sib} not a child of #{my_parent.pid}")
          return false
        end
      end

      next_sibling = self.class.find(next_sib)
      if (next_sibling.prev_sib != prev_sib) && (next_sibling.prev_sib != pid)
        logger.error("#{self.class.name} #{pid}:  invalid prev_sib #{prev_sib}")
        errors.add(:prev_sib, "invalid prev_sib #{prev_sib}")
        return false
      end
    end

    # Check my parentage.
    # OK to already be parent's child.
    unless (unset?(parent))
      # NOT OK if parent does not exist.
      if (my_parent.nil?)
        logger.error("#{self.class.name} #{pid}:  parent #{parent} does not exist")
        errors.add(:parent, 'parent node does not exist')
        return false
      end
    end

    # Check my children.
    children.each do |child|
      my_child = self.class.find(child)
      # NOT OK if child does not exist.
      if (my_child.nil?)
        logger.error("#{self.class.name} #{pid}:  child #{child} does not exist")
        errors.add(:child, 'child node does not exist')
        return false
      end
      # OK to already be this child's parent.
      # OK if child has no parent.
      # NOT OK if child has another parent.
      # TODO How to re-parent?
      if (my_child.parent != pid)
        logger.error("#{self.class.name} #{pid}:  child #{my_child.pid} has another parent:  #{my_child.parent}")
        errors.add(:child, 'child has another parent')
        return false
      end
    end

    # Persist myself.
    logger.info("Saving #{self.class.name} #{pid}")
    begin
      return false if ! super()
    rescue RestClient::BadRequest => e
      logger.error(e.message)
      errors[:base] << e.message
      errors[:base] << 'Check for a damaged or invalid file'
      return false
    end

    # Link myself to previous sibling.
    if (!unset?(prev_sib))
      prev_sibling = self.class.find(prev_sib)
      prev_sibling.next_sib = pid
      prev_sibling.save(unchecked: 1)
      logger.debug("Saving #{self.class.name} #{pid}:  prev_sib is #{prev_sib}")
    end

    # Link myself to next sibling.
    if (!unset?(next_sib))
      next_sibling = self.class.find(next_sib)
      next_sibling.prev_sib = pid
      next_sibling.save(unchecked: 1)
      logger.debug("Saving #{self.class.name} #{pid}:  next_sib is #{next_sib}")
    end

    # Link myself to my parent as a child.
    unless (unset?(parent))
      unless (my_parent.children.include?(pid))
        # This is really weird.  Multi-valued attributes have the usual array
        # operators but some of them do nothing.  The only way to augment one is
        # to augment a copy and assign the result back.  ?!?!
        my_parent.children = my_parent.children << pid
        my_parent.save(unchecked: 1)
      end
    end

    # Link my children to me as parent.
    children.each do |child|
      my_child = self.class.find(child)
      if (unset?(my_child.parent))
        my_child.parent = pid
        my_child.save(unchecked: 1)
      end
    end

    # Success!
    logger.info("Saved #{self.class.name} #{pid}")
    true
  end

  def save!(opts={}) # Added to debug tests
    raise(ActiveFedora::RecordInvalid, self, caller) unless save(opts)
  end

  # Unlink this node from siblings and parent.
  # Raises OrphanError if this node has children.
  def delete
    # Check for children.
    unless (children.empty?)
      logger.error("deleting #{self.class.name} #{pid}:  would leave orphans #{children.inspect}")
      raise OrphanError, children.inspect
    end

    # Load my siblings, if any.
    begin
      prev_sibling = self.class.find(prev_sib) if (!unset?(prev_sib))
    rescue ActiveFedora::ObjectNotFoundError => e
      logger.error("deleting #{self.class.name} #{pid}, missing prev_sib: #{e}")
    end

    begin
      next_sibling = self.class.find(next_sib) if (!unset?(next_sib))
    rescue ActiveFedora::ObjectNotFoundError => e
      logger.error("deleting #{self.class.name} #{pid}, missing next_sib: #{e}")
    end

    # Unlink from previous sibling.
    if (prev_sibling)
      prev_sibling.next_sib = next_sibling ? next_sibling.pid : nil
      prev_sibling.save(unchecked: 1)
    end

    # Unlink from next sibling.
    if (next_sibling)
      next_sibling.prev_sib = prev_sibling ? prev_sibling.pid : nil
      next_sibling.save(unchecked: 1)
    end

    # Load my parent, if any.
    begin
      my_parent = self.class.find(parent) unless (unset?(parent))
    rescue ActiveFedora::ObjectNotFoundError => e
      logger.error("deleting #{self.class.name} #{pid}, missing parent #{parent}: #{e}")
    end

    # Unlink from parent.
    if (my_parent)
      my_sibs = my_parent.children
      my_sibs.delete(pid)
      my_parent.children = my_sibs
      my_parent.save(unchecked: 1)
    end

    logger.info("Deleting #{self.class.name} #{pid}")
    super
    logger.info("Deleted #{self.class.name} #{pid}")
  end

  # Method returns ordered children and false
  # Or unordered children and an error message
  def order_children()
    ordered_children = Array.new
    error = false
    # Get first child and all child ids
    first_child = false
    next_child = false
    child_ids = Array.new
    self.children.each do |child|
      child_ids << child
      my_child = self.class.find(child)
      next if (!my_child.prev_sib.nil?) && (my_child.prev_sib != '')
      # Check for multiple first children
      if !first_child
        first_child = my_child
      else
        error = "Multiple First Children"
        return [self.children, error]
      end
    end
    if first_child
      next_child = first_child
    else
      # Check for no first child
      error = "No First Child Found"
      return [self.children, error]
    end
    my_children = Array.new
    while next_child do
      ordered_children << next_child
      np_id = next_child.next_sib
      if  np_id != nil && np_id != ''
        if my_children.include?(np_id)
          # Check for infinite loop
          error = "Infinite loop of children"
          next_child = false
        elsif child_ids.include?(np_id)
          # Find next child
          my_children << np_id
          next_child = self.class.find(np_id)
        else
          # Node has no parent
          error = "Node not Found in Listing - " + np_id.to_s
          next_child = false
        end
      else
        next_child = false
      end
    end
    # Check if all children are included
    if !error && ordered_children.count < self.children.count
      error = "Children Missing From List"
    end
    # Return unordered list if error occurs
    return [self.children, error] if error
    return [ordered_children.collect! {|child| child.pid}, error]
  end

end
