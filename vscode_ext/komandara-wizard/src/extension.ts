import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import {
	tclTemplate,
	headerTemplate,
	startupTemplate,
	mainTemplate,
	cmakeTemplate,
	toolchainTemplate,
	linkerTemplate,
	settingsJsonTemplate,
	settingsJsonGenesys2Template,
	launchJsonGenesys2,
	launchJsonSim,
	cmakeKitsJsonTemplate,
	tasksJsonTemplate
} from './templates';
import { KOMANDARA_ROOT } from './config';

export function activate(context: vscode.ExtensionContext) {
	console.log('Komandara Wizard is now active!');

	const disposable = vscode.commands.registerCommand('komandara-wizard.createProject', async () => {
		// 1. Select the target board
		const boardOptions = ['Genesys 2', 'Simulation'];
		const targetBoard = await vscode.window.showQuickPick(boardOptions, {
			placeHolder: 'Select the target board for the new Komandara project',
		});

		if (!targetBoard) {
			return; // Cancelled
		}

		// 2. Select folder to scaffold the project into
		const defaultUri = vscode.workspace.workspaceFolders ? vscode.workspace.workspaceFolders[0].uri : undefined;
		const folderUri = await vscode.window.showOpenDialog({
			canSelectFiles: false,
			canSelectFolders: true,
			canSelectMany: false,
			openLabel: 'Create Project Here',
			defaultUri: defaultUri
		});

		if (!folderUri || folderUri.length === 0) {
			return; // Cancelled
		}

		const projectPath = folderUri[0].fsPath;
		const isGenesys2 = targetBoard === 'Genesys 2';

		// 3. Retrieve Compile-Time Absolute Komandara Root Path
		// Normalize paths for CMake / JSON compatibility
		const normalizedRoot = KOMANDARA_ROOT.replace(/\\\\/g, '/');

		try {
			// Scaffold directory structure
			const includeDir = path.join(projectPath, 'include');
			const vscodeDir = path.join(projectPath, '.vscode');
			const openocdDir = path.join(projectPath, 'openocd');

			fs.mkdirSync(includeDir, { recursive: true });
			fs.mkdirSync(vscodeDir, { recursive: true });

			if (isGenesys2) {
				fs.mkdirSync(openocdDir, { recursive: true });
			}

			// Write core source files
			fs.writeFileSync(path.join(includeDir, 'k10.h'), headerTemplate);
			fs.writeFileSync(path.join(projectPath, 'startup.S'), startupTemplate);
			fs.writeFileSync(path.join(projectPath, 'main.c'), mainTemplate);

			// Write CMake infrastructure
			fs.writeFileSync(path.join(projectPath, 'CMakeLists.txt'), cmakeTemplate);
			fs.writeFileSync(path.join(projectPath, 'k10_link.ld'), linkerTemplate);

			const toolchainContent = toolchainTemplate.replace(/\$KOMANDARA_ROOT/g, normalizedRoot);
			fs.writeFileSync(path.join(projectPath, 'riscv32.cmake'), toolchainContent);

			// Write VSCode configuration
			const settingsTemplate = isGenesys2 ? settingsJsonGenesys2Template : settingsJsonTemplate;
			const settingsContent = settingsTemplate.replace(/\$KOMANDARA_ROOT/g, normalizedRoot);
			fs.writeFileSync(path.join(vscodeDir, 'settings.json'), settingsContent);

			fs.writeFileSync(path.join(vscodeDir, 'cmake-kits.json'), cmakeKitsJsonTemplate);
			fs.writeFileSync(path.join(vscodeDir, 'tasks.json'), tasksJsonTemplate);

			// Board specific files
			if (isGenesys2) {
				fs.writeFileSync(path.join(openocdDir, 'board-openocd-cfg.tcl'), tclTemplate);

				const launchContent = launchJsonGenesys2.replace(/\$KOMANDARA_ROOT/g, normalizedRoot);
				fs.writeFileSync(path.join(vscodeDir, 'launch.json'), launchContent);

				// Re-write CMakeLists to inject the hardware define
				const hwCmake = cmakeTemplate.replace('add_executable(k10_app main.c startup.S)', 'set(K10_REAL_HW 1)\nadd_executable(k10_app main.c startup.S)');
				fs.writeFileSync(path.join(projectPath, 'CMakeLists.txt'), hwCmake);

			} else {
				const launchContent = launchJsonSim.replace(/\$KOMANDARA_ROOT/g, normalizedRoot);
				fs.writeFileSync(path.join(vscodeDir, 'launch.json'), launchContent);
			}

			vscode.window.showInformationMessage(`Komandara Project created successfully for ${targetBoard}!`, 'Open Folder').then(selection => {
				if (selection === 'Open Folder') {
					vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(projectPath), true);
				}
			});

		} catch (error) {
			vscode.window.showErrorMessage('Error creating project: ' + error);
		}
	});

	context.subscriptions.push(disposable);
}

export function deactivate() { }
