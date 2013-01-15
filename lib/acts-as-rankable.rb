module ActsAsRankable
  extend ActiveSupport::Concern
  MaxRank = 2147483647
  MinRank = -MaxRank
  
  included do
    
  end
  
  def update_attributes(*args)
    unless args.first[ClassMethods.attribute].nil?
      self.send("#{ClassMethods.attribute}=", args.first[ClassMethods.attribute])
      args.first.delete(ClassMethods.attribute)
    end
    super
  end
  
  def previous_record
    self.class.with_rank(self.send(ClassMethods.attribute) - 1)
  end
  
  def next_record
    self.class.with_rank(self.send(ClassMethods.attribute) + 1)
  end
 

private
  def initialize_rank
    next_rank = self.class.next_rank
    self.send("#{ClassMethods.attribute}=", next_rank) if @rank.nil? || @rank > next_rank || @rank < 0
  end

  def internal_rank=(val)
    self.send("#{ClassMethods.db_field}=", val)
  end

  def internal_rank
    self.send(ClassMethods.db_field)
  end

  def shift_internal_rank_up!
     my_internal_rank = self.send(:internal_rank)
     the_next_record = next_record
     next_internal_rank = the_next_record ? the_next_record.send(:internal_rank) : MaxRank
     if next_internal_rank - my_internal_rank < 2
       self.class.redistribute_ranks!
       return
     end
     new_internal_rank = ((my_internal_rank + next_internal_rank) / 2).to_i
     self.update_attribute(ClassMethods.db_field, new_internal_rank)
   end

   def shift_internal_rank_down!
     my_internal_rank = self.send(:internal_rank)
     the_previous_record = previous_record
     previous_internal_rank = the_previous_record ? the_previous_record.send(:internal_rank) : MinRank
     if my_internal_rank - previous_internal_rank < 2
       self.class.redistribute_ranks!
       return
     end
     new_internal_rank = ((my_internal_rank + previous_internal_rank) / 2).to_i
   
     self.update_attribute(ClassMethods.db_field, new_internal_rank)
   end

  def set_internal_rank
    @rank = 0 if @rank < 0
    next_rank = self.class.next_rank
    @rank = next_rank if @rank > next_rank    
  
    if self.send(ClassMethods.db_field).nil? # ready to be reset
      if next_rank == 0
        self.send(:internal_rank=, MinRank)
      else
        current_rank_holder = self.class.with_rank(@rank)
        if current_rank_holder
          current_rank_holder_internal_rank = current_rank_holder.send(:internal_rank)
          current_rank_holder.send(:shift_internal_rank_up!)
          self.send(:internal_rank=, current_rank_holder_internal_rank)
        else
          previous_rank_holder = self.class.with_rank(@rank - 1)
          next_rank_holder = self.class.with_rank(@rank + 1)
        
          if next_rank_holder.nil?
            if previous_rank_holder.nil?
              debugger
            end
            if previous_rank_holder.send(:internal_rank) >= MaxRank - 2
                previous_rank_holder.send(:shift_internal_rank_down!)
            end
            self.send(:internal_rank=, ((previous_rank_holder.send(:internal_rank) + MaxRank) / 2).to_i)
          end
        end
      end
    else
      self.update_attribute(ClassMethods.db_field, nil)
      set_internal_rank
    end
  end
  
  
  module ClassMethods
    mattr_accessor :attribute
    mattr_accessor :db_field
    
    def acts_as_rankable(attribute, opts = {})
      self.attribute = attribute
      
      send :define_method, self.attribute do
        self.reload
        self.class.filtered.lt(ClassMethods.db_field => self.send(ClassMethods.db_field)).count
      end
      
      send :define_method, "#{self.attribute.to_s}=".to_sym do |val|
        @rank = val.to_i
        set_internal_rank        
      end
      
      self.db_field = "_#{attribute.to_s}".to_sym
      field self.db_field, :type => Integer
      index self.db_field => 1
      before_create :initialize_rank

      scope :filtered, excludes(self.db_field => nil)
      scope :ranked, order_by(self.db_field => 1)
    end
    
    def with_rank(position, scope = nil)
      self.filtered.ranked.offset(position).first
    end
    
    def redistribute_ranks!
      rank_step = MaxRank / (self.count + 2)
      current_rank = rank_step
      self.order_by(self.db_field => 1).each do |atom|
        atom.update_attribute(self.db_field, current_rank)
        current_rank += rank_step
      end
    end
    
    def next_rank
      self.filtered.count
    end
  end
end
