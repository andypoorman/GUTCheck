class_name GUTCheckBranchInfo
## A branch point for BRDA coverage. Each condition (if/elif/while) produces
## two BranchInfo entries (true and false). Match patterns produce one each.


var line_number: int   # Source line of the branch
var block_id: int      # Same block_id = same if/elif/else chain or match
var branch_id: int     # Branch index within the block (0-based)
var probe_id: int      # Which probe in the hits array tracks this branch
## True for the true-path of a condition.
var is_true_branch: bool

func _init(p_line: int, p_block: int, p_branch: int, p_probe: int, p_is_true: bool = true):
	line_number = p_line
	block_id = p_block
	branch_id = p_branch
	probe_id = p_probe
	is_true_branch = p_is_true
